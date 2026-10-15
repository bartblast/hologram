"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Config from "../../assets/js/config.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Mutations from "../../assets/js/mutations.mjs";
import Replica from "../../assets/js/replica.mjs";

describe("Mutations", () => {
  describe("send()", () => {
    let fetchStub, originalHologram, originalInstanceId;

    const batch = {
      seq: 7,
      writes: [
        {
          claim: null,
          data: {title: "alpha"},
          id: "018f0000-0000-7000-8000-000000000001",
          op: "create",
          stamp: 1_798_246_400_125_952,
          type: "MyApp.Task",
        },
      ],
    };

    const responding = (body, status = 200) =>
      (fetchStub = sinon.stub(globalThis, "fetch").resolves({
        json: async () => body,
        ok: status >= 200 && status < 300,
        status,
        text: async () => (typeof body === "string" ? body : ""),
      }));

    beforeEach(() => {
      originalHologram = globalThis.Hologram;

      globalThis.Hologram = {
        csrfToken: "test-csrf-token-123",
        sync: {modelHash: "test-model-hash"},
      };

      Replica.adopt({id: "test-replica-id", token: "test-replica-token"});

      originalInstanceId = App.instanceId;
      App.instanceId = "test-instance-id";
    });

    afterEach(() => {
      sinon.restore();
      globalThis.Hologram = originalHologram;
      App.instanceId = originalInstanceId;
      Replica.reset();
    });

    it("posts the batch to the mutation endpoint", async () => {
      responding({dropped: {}, status: "confirmed"});

      await Mutations.send(batch);

      assert.equal(fetchStub.firstCall.args[0], "/hologram/mutation");
      assert.equal(fetchStub.firstCall.args[1].method, "POST");

      assert.deepStrictEqual(fetchStub.firstCall.args[1].headers, {
        "Content-Type": "application/json",
        "X-Csrf-Token": "test-csrf-token-123",
      });
    });

    // The identity is whatever pair the browser is presenting - the page's on a first visit, the
    // one it remembered on every visit after that - and this client invents neither half of it.
    it("sends the envelope the endpoint parses", async () => {
      responding({dropped: {}, status: "confirmed"});

      await Mutations.send(batch);

      assert.deepStrictEqual(JSON.parse(fetchStub.firstCall.args[1].body), {
        instance_id: "test-instance-id",
        model_hash: "test-model-hash",
        replica_id: "test-replica-id",
        replica_token: "test-replica-token",
        seq: 7,
        writes: batch.writes,
      });
    });

    // Both halves of a confirmation reach the caller: what this client's write lost, and the value
    // standing in its place with the revision it carries. The second is what lets a losing write
    // give way to the winner as the answer lands, rather than to whatever the row held before
    // either of them - which is a value nobody wrote.
    it("answers a confirmation with what lost and what stands", async () => {
      responding({
        dropped: {0: {title: "Standup"}},
        kept: {0: {title: "Retro", $revisions: {title: 1_756_100_000_123_004}}},
        status: "confirmed",
      });

      assert.deepStrictEqual(await Mutations.send(batch), {
        dropped: {0: {title: "Standup"}},
        kept: {0: {title: "Retro", $revisions: {title: 1_756_100_000_123_004}}},
        status: "confirmed",
      });
    });

    it("answers a confirmation that lost nothing with both halves empty", async () => {
      responding({dropped: {}, kept: {}, status: "confirmed"});

      assert.deepStrictEqual(await Mutations.send(batch), {
        dropped: {},
        kept: {},
        status: "confirmed",
      });
    });

    // The reason travels as an encoded client term, because it carries regexes, ranges and
    // exception structs - and it is handed on exactly as it arrived, so what this answers stays a
    // plain JSON value. Reading the term is the queue's, at the one place it is looked at.
    it("answers a rejection as the server spelled it", async () => {
      responding({
        reason: 'Type.atom("stale_build")',
        status: "rejected",
        write: null,
      });

      assert.deepStrictEqual(await Mutations.send(batch), {
        reason: 'Type.atom("stale_build")',
        status: "rejected",
        write: null,
      });
    });

    it("names the write a rejection refused", async () => {
      responding({
        reason: 'Type.atom("not_found")',
        status: "rejected",
        write: 2,
      });

      assert.equal((await Mutations.send(batch)).write, 2);
    });

    // A 403 says the identity was refused before the writes were read, so it is not a verdict
    // about them - the batch is still pending, and what to do about it is the sender's call.
    it("answers a failure for a status carrying no verdict", async () => {
      responding({}, 403);

      assert.deepStrictEqual(await Mutations.send(batch), {
        httpStatus: 403,
        status: "failed",
      });
    });

    it("answers a failure for a server error", async () => {
      responding({}, 500);

      assert.deepStrictEqual(await Mutations.send(batch), {
        httpStatus: 500,
        status: "failed",
      });
    });

    it("clears the deadline once the answer is read", async () => {
      const timers = sinon.useFakeTimers();

      let signal;

      sinon.stub(globalThis, "fetch").callsFake((_url, opts) => {
        signal = opts.signal;

        return Promise.resolve({
          json: async () => ({dropped: {}, status: "confirmed"}),
          ok: true,
          status: 200,
        });
      });

      await Mutations.send(batch);
      await timers.tickAsync(Config.mutationTimeoutMs);

      assert.isFalse(signal.aborted);
    });

    // A malformed envelope is this client's own bug, not an answer about the writes.
    it("raises for an envelope the endpoint could not parse", async () => {
      responding("seq must be a non-negative integer", 400);

      let errorThrown = false;

      try {
        await Mutations.send(batch);
      } catch (error) {
        errorThrown = true;
        assert.instanceOf(error, HologramRuntimeError);

        assert.equal(
          error.message,
          "mutation failed: seq must be a non-negative integer",
        );
      }

      assert.isTrue(errorThrown, "Expected HologramRuntimeError to be thrown");
    });

    it("lets a network failure through to the caller", async () => {
      sinon.stub(globalThis, "fetch").rejects(new Error("offline"));

      let errorThrown = false;

      try {
        await Mutations.send(batch);
      } catch (error) {
        errorThrown = true;
        assert.equal(error.message, "offline");
      }

      assert.isTrue(errorThrown, "Expected the failure to reach the caller");
    });

    // Left to itself a request that connects and goes quiet never settles, and the sender loop
    // holds its guard until it does - so the queue would be stopped for the life of the page.
    it("gives up on a request that never answers", async () => {
      const timers = sinon.useFakeTimers();

      sinon.stub(globalThis, "fetch").callsFake(
        (_url, opts) =>
          new Promise((_resolve, reject) => {
            opts.signal.addEventListener("abort", () =>
              reject(opts.signal.reason),
            );
          }),
      );

      let errorThrown = false;

      const caught = Mutations.send(batch).catch((error) => {
        errorThrown = true;

        return error;
      });

      await timers.tickAsync(Config.mutationTimeoutMs);

      assert.isTrue(errorThrown, "Expected the deadline to end the request");
      assert.equal((await caught).name, "AbortError");
    });

    // A body that never streams is the same silence as a request that never answers, so the
    // deadline covers reading the answer and not just receiving the response.
    it("gives up on an answer whose body never arrives", async () => {
      const timers = sinon.useFakeTimers();

      let signal;

      sinon.stub(globalThis, "fetch").callsFake((_url, opts) => {
        signal = opts.signal;

        return Promise.resolve({
          json: () => new Promise(() => {}),
          ok: true,
          status: 200,
        });
      });

      Mutations.send(batch);

      await timers.tickAsync(Config.mutationTimeoutMs);

      assert.isTrue(signal.aborted);
    });
  });
});

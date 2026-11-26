"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Client from "../../assets/js/client.mjs";
import Config from "../../assets/js/config.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import IdentityTracker from "../../assets/js/identity_tracker.mjs";
import Mutations from "../../assets/js/mutations.mjs";
import Replica from "../../assets/js/replica.mjs";

describe("Mutations", () => {
  describe("send()", () => {
    let fetchStub, originalHologram, originalInstanceId;

    const batch = {
      actorUserId: "i42",
      seq: 7,
      writes: [
        {
          data: {title: "alpha"},
          id: "02wLIRxqmq3AUo6vl2OW37",
          op: "create",
          stamp: 1_798_246_400_125_952,
          type: "MyApp.Task",
        },
      ],
    };

    const responding = (body, status = 200, identityTag = null) =>
      (fetchStub = sinon.stub(globalThis, "fetch").resolves({
        headers: new Headers(
          identityTag ? {"hologram-identity-tag": identityTag} : {},
        ),
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
        actor_user_id: "i42",
        instance_id: "test-instance-id",
        model_hash: "test-model-hash",
        replica_id: "test-replica-id",
        replica_token: "test-replica-token",
        seq: 7,
        writes: batch.writes,
      });
    });

    // The server applies a batch as the session's user, so it has to know whose this one is.
    it("names a visitor's batch as nobody's", async () => {
      responding({dropped: {}, status: "confirmed"});

      await Mutations.send({...batch, actorUserId: null});

      const body = JSON.parse(fetchStub.firstCall.args[1].body);

      assert.property(body, "actor_user_id");
      assert.isNull(body.actor_user_id);
    });

    it("sends a big integer as its digits", async () => {
      responding({dropped: {}, status: "confirmed"});

      await Mutations.send({
        ...batch,
        writes: [
          {data: {n: 9007199254740993n}, deltas: {m: -9007199254740993n}},
        ],
      });

      assert.deepStrictEqual(
        JSON.parse(fetchStub.firstCall.args[1].body).writes,
        [{data: {n: "9007199254740993"}, deltas: {m: "-9007199254740993"}}],
      );
    });

    // A batch queued before the browser mended these holds the surrogate as it was typed, and the
    // server's JSON parser would refuse the whole body for it.
    it("sends a lone surrogate as U+FFFD", async () => {
      responding({dropped: {}, status: "confirmed"});

      await Mutations.send({
        ...batch,
        writes: [{data: {title: "a\uD800b"}}],
      });

      const {body} = fetchStub.firstCall.args[1];

      assert.notInclude(body.toLowerCase(), "\\ud800");

      assert.deepStrictEqual(JSON.parse(body).writes, [
        {data: {title: "a\uFFFDb"}},
      ]);
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
          headers: new Headers(),
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

    // A tab that only saves sends no command, and a stream that missed the change answers each of
    // its saves with a conflict.
    describe("checking the stream against the identity", () => {
      let catchingUp, originalDataLayer;

      beforeEach(() => {
        IdentityTracker.init("1.tag-1");

        originalDataLayer = Hologram.dataLayer;
        catchingUp = sinon.spy();

        Hologram.dataLayer = {catchUpIdentity: catchingUp};
      });

      afterEach(() => {
        Hologram.dataLayer = originalDataLayer;

        IdentityTracker.documentPeriod = null;
        IdentityTracker.period = null;
        IdentityTracker.periods = new Set();
        IdentityTracker.tag = null;
      });

      it("checks after taking in the reply's tag", async () => {
        let tagSeen;

        Hologram.dataLayer = {
          catchUpIdentity: () => (tagSeen = IdentityTracker.tag),
        };

        responding({dropped: {}, status: "confirmed"}, 200, "2.tag-2");

        await Mutations.send(batch);

        assert.equal(tagSeen, "2.tag-2");
      });

      it("checks on a conflict", async () => {
        responding({}, 409, "2.tag-2");

        assert.deepStrictEqual(await Mutations.send(batch), {
          httpStatus: 409,
          status: "failed",
        });

        sinon.assert.calledOnce(catchingUp);
      });

      it("checks on an envelope the endpoint could not parse", async () => {
        responding("seq must be a non-negative integer", 400, "2.tag-2");

        let thrownError = null;

        try {
          await Mutations.send(batch);
        } catch (error) {
          thrownError = error;
        }

        assert.instanceOf(thrownError, HologramRuntimeError);
        sinon.assert.calledOnce(catchingUp);
      });

      // The server's answer can move the identity the client knows.
      it("checks a reply no newer than what the client knows once the server has answered", async () => {
        IdentityTracker.observe("3.tag-3");

        let answer;

        sinon
          .stub(Client, "settleIdentity")
          .returns(new Promise((resolve) => (answer = resolve)));

        responding({}, 409, "2.tag-2");

        await Mutations.send(batch);

        sinon.assert.notCalled(catchingUp);

        answer();
        await Promise.resolve();

        sinon.assert.calledOnce(catchingUp);
      });

      it("checks nothing when no reply came", async () => {
        sinon.stub(globalThis, "fetch").rejects(new Error("offline"));

        try {
          await Mutations.send(batch);
        } catch {
          // The failure reaches the caller.
        }

        sinon.assert.notCalled(catchingUp);
      });
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
          headers: new Headers(),
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

"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Client from "../../assets/js/client.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Sse from "../../assets/js/sse.mjs";

defineRuntimeGlobals();

describe("Batches", () => {
  const TAG = "MyApp.Tag";
  const TODO = "MyApp.Todo";

  const write = (id) => ({id, op: "delete", stamp: 1, type: TODO});

  beforeEach(() => {
    Batches.reset();
  });

  afterEach(() => {
    Batches.reset();
  });

  const wrote = (id) => {
    Batches.current().append(write(id));
  };

  describe("flush()", () => {
    const STAMP = 1_798_246_400_125_952;

    let renderStub, sendStub;

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TODO]: {
            attributes: {
              created_at: "datetime",
              done: "boolean",
              id: "uuid",
              title: "string",
              updated_at: "datetime",
            },
            constraints: {},
            defaults: {},
            enumValues: {},
            frameworkAttributes: [],
            relationships: {tags: {optional: true, toMany: true, type: TAG}},
            serverOnly: [],
          },
        },
      };

      LocalDatabase.reset();
      Model.reset();

      renderStub = sinon.stub(Sse, "scheduleRender");
      sendStub = sinon.stub(Client, "sendMutation");
    });

    afterEach(() => {
      sinon.restore();
      LocalDatabase.reset();
    });

    const confirmed = (dropped = {}) => ({dropped, status: "confirmed"});

    const creating = (id, title) => ({
      claim: null,
      data: {done: false, title},
      id,
      op: "create",
      stamp: STAMP,
      type: TODO,
    });

    const sealed = (...writes) => {
      Batches.open("todos");

      for (const write of writes) {
        Batches.current().append(write);
      }

      return Batches.close();
    };

    it("sends the pending batches oldest first, one at a time", async () => {
      sealed(creating("t1", "first"));
      sealed(creating("t2", "second"));

      let inFlight = 0;

      sendStub.callsFake(async () => {
        inFlight += 1;
        assert.equal(inFlight, 1, "two batches were in flight at once");
        await Promise.resolve();
        inFlight -= 1;

        return confirmed();
      });

      await Batches.flush();

      assert.deepStrictEqual(
        sendStub.getCalls().map((call) => call.args[0].seq),
        [1, 2],
      );
    });

    it("does not enter the loop twice", async () => {
      sealed(creating("t1", "first"));
      sendStub.resolves(confirmed());

      await Promise.all([Batches.flush(), Batches.flush()]);

      sinon.assert.calledOnce(sendStub);
    });

    // A confirmed batch's values ARE what the server stored, so they move into the base and the
    // layer goes - and what a reader sees does not change across the move.
    it("writes a confirmed batch's rows into the base and drops its layer", async () => {
      sealed(creating("t1", "first"));
      sendStub.resolves(confirmed());

      await Batches.flush();

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "first");
      assert.equal(LocalDatabase.baseRow(TODO, "t1").$revisions.title, STAMP);
      assert.isFalse(Overlay.names(TODO, "t1"));
      assert.deepStrictEqual(Batches.pending, []);
    });

    it("takes a confirmed delete out of the base", async () => {
      LocalDatabase.putRow(TODO, {done: false, id: "t1", title: "held"});

      sealed({
        based_on: {},
        claim: null,
        id: "t1",
        op: "delete",
        stamp: STAMP,
        type: TODO,
      });

      sendStub.resolves(confirmed());

      await Batches.flush();

      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("records a confirmed edge in the base", async () => {
      sealed({
        claim: null,
        id: "t1",
        op: "add_relationship",
        relationship: "tags",
        target_id: "g1",
        type: TODO,
      });

      sendStub.resolves(confirmed());

      await Batches.flush();

      assert.deepStrictEqual(
        LocalDatabase.baseTargetIds(TODO, "tags", "t1"),
        new Set(["g1"]),
      );
    });

    // The value lost the merge, so the base keeps what it has and the winner arrives with the
    // frame - promoting the client's value would put back the value the server refused.
    it("leaves a dropped column as the base holds it", async () => {
      LocalDatabase.putRow(TODO, {
        done: false,
        id: "t1",
        title: "theirs",
        $revisions: {title: 99},
      });

      sealed({
        based_on: {title: 98},
        claim: null,
        data: {title: "mine"},
        id: "t1",
        op: "update",
        stamp: STAMP,
        type: TODO,
      });

      sendStub.resolves(confirmed({0: {title: "mine"}}));

      await Batches.flush();

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "theirs");
      assert.equal(LocalDatabase.baseRow(TODO, "t1").$revisions.title, 99);
    });

    // A later batch is still pending over the same row, and its values are not the server's to
    // store - so the two batches touch DIFFERENT fields here, which is the only shape where
    // promoting the folded row rather than the base row shows up.
    it("keeps a later batch's writes out of an earlier one's promotion", async () => {
      LocalDatabase.putRow(TODO, {
        done: false,
        id: "t1",
        title: "held",
        $revisions: {done: 10, title: 11},
      });

      Batches.open("todos");

      Batches.current().append({
        based_on: {title: 11},
        claim: null,
        data: {title: "first"},
        id: "t1",
        op: "update",
        stamp: STAMP,
        type: TODO,
      });

      Batches.close();
      Batches.open("todos");

      Batches.current().append({
        based_on: {done: 10},
        claim: null,
        data: {done: true},
        id: "t1",
        op: "update",
        stamp: STAMP + 1,
        type: TODO,
      });

      Batches.close();

      sendStub.onFirstCall().resolves(confirmed());
      sendStub.onSecondCall().resolves({httpStatus: 503, status: "failed"});

      await Batches.flush();

      const base = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(base.title, "first");
      assert.isFalse(base.done, "the pending batch's value reached the base");
      assert.equal(base.$revisions.done, 10);

      // The reader still sees both, because the second batch is still folded on top.
      assert.isTrue(LocalDatabase.getRow(TODO, "t1").done);
    });

    it("takes a rejected batch's rows away and keeps what the server said", async () => {
      sealed(creating("t1", "first"));

      sendStub.resolves({
        reason: "the reason",
        status: "rejected",
        write: 0,
      });

      await Batches.flush();

      assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      assert.deepStrictEqual(Batches.pending, []);
      assert.equal(Batches.rejected.length, 1);
      assert.equal(Batches.rejected[0].seq, 1);
      assert.equal(Batches.rejected[0].reason, "the reason");
      assert.equal(Batches.rejected[0].write, 0);
      assert.equal(Batches.rejected[0].state, "rejected");
    });

    it("leaves a batch nobody answered pending, and stops the queue behind it", async () => {
      sealed(creating("t1", "first"));
      sealed(creating("t2", "second"));

      sendStub.onFirstCall().resolves({httpStatus: 503, status: "failed"});
      sendStub.onSecondCall().resolves(confirmed());

      await Batches.flush();

      sinon.assert.calledOnce(sendStub);

      assert.deepStrictEqual(
        Batches.pending.map((batch) => batch.seq),
        [1, 2],
      );

      assert.equal(Batches.pending[0].state, "pending");
      assert.deepStrictEqual(Batches.rejected, []);
    });

    it("keeps a failed batch's rows on screen", async () => {
      sealed(creating("t1", "first"));
      sendStub.resolves({httpStatus: 503, status: "failed"});

      await Batches.flush();

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "first");
      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("sends it again on the next flush", async () => {
      sealed(creating("t1", "first"));

      sendStub.onFirstCall().resolves({httpStatus: 503, status: "failed"});
      sendStub.onSecondCall().resolves(confirmed());

      await Batches.flush();
      await Batches.flush();

      sinon.assert.calledTwice(sendStub);
      assert.deepStrictEqual(Batches.pending, []);
      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "first");
    });

    // Nobody said anything about the writes either way, so a dropped connection is the same
    // answer as a status carrying no verdict.
    it("reads a network failure as no answer at all", async () => {
      sealed(creating("t1", "first"));
      sendStub.rejects(new Error("offline"));

      await Batches.flush();

      assert.equal(Batches.pending.length, 1);
      assert.equal(Batches.pending[0].state, "pending");
      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "first");
    });

    // A malformed envelope is this client's own bug - retrying it forever would hide that.
    it("lets a malformed envelope raise rather than retrying it", async () => {
      sealed(creating("t1", "first"));
      sendStub.rejects(new HologramRuntimeError("mutation failed: nope"));

      let errorThrown = false;

      try {
        await Batches.flush();
      } catch (error) {
        errorThrown = true;
        assert.equal(error.message, "mutation failed: nope");
      }

      assert.isTrue(errorThrown, "Expected HologramRuntimeError to be thrown");
      assert.equal(Batches.pending[0].state, "pending");
    });

    it("can be entered again after a send that raised", async () => {
      sealed(creating("t1", "first"));
      sendStub
        .onFirstCall()
        .rejects(new HologramRuntimeError("mutation failed: nope"));
      sendStub.onSecondCall().resolves(confirmed());

      try {
        await Batches.flush();
      } catch {
        // Asserted on above - what matters here is that the loop released its guard.
      }

      await Batches.flush();

      assert.deepStrictEqual(Batches.pending, []);
    });

    it("schedules a render per answer", async () => {
      sealed(creating("t1", "first"));
      sealed(creating("t2", "second"));
      sendStub.resolves(confirmed());

      await Batches.flush();

      sinon.assert.calledTwice(renderStub);
    });

    it("does nothing when nothing is pending", async () => {
      await Batches.flush();

      sinon.assert.notCalled(sendStub);
    });
  });

  describe("close()", () => {
    it("seals the open batch and queues it", () => {
      Batches.open("todos");
      wrote("t1");

      const batch = Batches.close();

      assert.equal(batch.seq, 1);
      assert.equal(batch.state, "pending");
      assert.deepStrictEqual(Batches.pending, [batch]);
    });

    it("takes the next sequence number per batch that ships", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 2);
    });

    it("drops a batch that collected nothing, spending no sequence number", () => {
      Batches.open("todos");

      assert.isNull(Batches.close());
      assert.deepStrictEqual(Batches.pending, []);

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 1);
    });

    it("leaves a sealed batch in the overlay, where its rows read as applied", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      assert.equal(Overlay.durability(TODO, "t1"), "applied");
    });

    it("closes the batch opened last", () => {
      const outer = Batches.open("outer");
      const inner = Batches.open("inner");

      wrote("t1");

      assert.strictEqual(Batches.close(), inner);
      assert.strictEqual(Batches.current(), outer);
    });

    it("answers nothing when no batch is open", () => {
      assert.isNull(Batches.close());
    });
  });

  describe("current()", () => {
    it("answers nothing when no action has opened one", () => {
      assert.isNull(Batches.current());
    });

    it("answers the batch opened last", () => {
      Batches.open("outer");

      const inner = Batches.open("inner");

      assert.strictEqual(Batches.current(), inner);
    });
  });

  describe("discard()", () => {
    it("takes the batch's writes out of the overlay", () => {
      Batches.open("todos");
      wrote("t1");

      Batches.discard();

      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    it("does not queue it, and spends no sequence number", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.discard();

      assert.deepStrictEqual(Batches.pending, []);

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 1);
    });

    it("discards the batch opened last", () => {
      const outer = Batches.open("outer");

      Batches.open("inner");
      Batches.discard();

      assert.strictEqual(Batches.current(), outer);
    });

    it("answers nothing when no batch is open", () => {
      assert.isNull(Batches.discard());
    });
  });

  describe("open()", () => {
    it("names the component the action ran on", () => {
      assert.equal(Batches.open("todos").target, "todos");
    });

    it("puts the batch in the overlay at once, so an action reads its own writes", () => {
      Batches.open("todos");
      wrote("t1");

      assert.isTrue(Overlay.names(TODO, "t1"));
    });
  });

  describe("reset()", () => {
    it("drops the open, the queued and the overlay's own", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();
      Batches.open("todos");

      Batches.reset();

      assert.isNull(Batches.current());
      assert.deepStrictEqual(Batches.pending, []);
      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    it("starts the sequence numbers over", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      Batches.reset();

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 1);
    });
  });
});

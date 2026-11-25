"use strict";

// Imported by path and installed by hand for the tests that need a real store, for the reasons
// durability_test.mjs gives.
import fakeIndexedDB from "../../assets/node_modules/fake-indexeddb/build/esm/fakeIndexedDB.js";
import FDBKeyRange from "../../assets/node_modules/fake-indexeddb/build/esm/FDBKeyRange.js";

import {
  assert,
  defineRuntimeGlobals,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Batches from "../../assets/js/batches.mjs";
import Clock from "../../assets/js/clock.mjs";
import Durability from "../../assets/js/durability.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Model from "../../assets/js/model.mjs";
import Mutations from "../../assets/js/mutations.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Replica from "../../assets/js/replica.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Sse from "../../assets/js/sse.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("Batches", () => {
  const TAG = "MyApp.Tag";
  const TODO = "MyApp.Todo";

  const write = (id) => ({id, op: "delete", stamp: 1, type: TODO});

  // Shared by every describe that needs a write to FOLD - the overlay builds a created row from
  // the model's settable fields, so a fold against no model is a fold of nothing.
  const TODO_MODEL = {
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
  };

  beforeEach(() => {
    Batches.reset();
  });

  afterEach(() => {
    Batches.reset();

    // Module state of another module's, like the store's mode below: a test that follows must put
    // the tab back in the lead, or every test after it sends nothing.
    Tabs.leader = true;

    // Module state, and not Batches's to reset: this suite runs the store in memory mode, so a
    // test that puts it in another leaves every test after it - in this file and in the next -
    // filing batches into a database that is not there.
    Durability.mode = "memory";

    // Not covered by LocalDatabase.reset(), which leaves the acting user alone on purpose - a
    // resync replaces what the server said and does not change who is signed in. So a test that
    // sets one has to put it back, or it reaches every suite that runs after this file.
    LocalDatabase.actorUserId = null;
    LocalDatabase.actorEntityId = null;

    Replica.reset();
    sinon.restore();
  });

  const wrote = (id) => {
    Batches.current().append(write(id));
  };

  describe("takeLanded()", () => {
    beforeEach(() => {
      sinon.stub(SyncStream, "scheduleRender");
    });

    const held = (seq, landed = []) => ({
      actorUserId: null,
      landed,
      seq,
      writes: [write("t1"), write("t2")],
    });

    // A stored frame landed it while this tab held it unlanded.
    it("adds the marks the store records to a batch this tab holds", () => {
      Batches.adopt([held(7, [1])]);

      Batches.takeLanded([{landed: [0], seq: 7}]);

      assert.deepStrictEqual(Batches.pending[0].record().landed, [0, 1]);
    });

    it("passes over a batch this tab does not hold", () => {
      Batches.adopt([held(7)]);

      Batches.takeLanded([{landed: [0], seq: 8}]);

      assert.deepStrictEqual(Batches.pending[0].record().landed, []);
    });
  });

  describe("flush()", () => {
    const STAMP = 1_798_246_400_125_952;

    let renderStub, sendStub;

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.reset();
      Model.reset();

      renderStub = sinon.stub(SyncStream, "scheduleRender");
      sendStub = sinon.stub(Mutations, "send");
    });

    afterEach(() => {
      sinon.restore();
      LocalDatabase.reset();

      SyncStream.stopReason = null;
    });

    const confirmed = (dropped = {}, kept = {}) => ({
      dropped,
      kept,
      status: "confirmed",
    });

    const creating = (id, title) => ({
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

    // A batch made in any tab is filed in the one queue they share, so a follower that sent as well
    // would put a second copy of every batch on the wire under the same replica and number.
    it("sends nothing from a tab that does not lead the group", async () => {
      Tabs.leader = false;

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isFalse(sendStub.called);
      assert.equal(Batches.pending.length, 1);
    });

    // Before its restore a tab that leads holds its page's identity, not the one the stored queue
    // was numbered under - and has not taken that queue up. Ready, it sends.
    it("sends nothing from a tab that leads its group until it is ready", async () => {
      const reading = sinon.stub(Durability, "queuedBatches").resolves([]);

      sendStub.resolves(confirmed());

      try {
        assert.isTrue(
          await Tabs.join("hologram.1.batches-flush.anonymous", {
            onLead: () => {},
            onMessage: () => {},
          }),
        );

        sealed(creating("t1", "first"));

        await Batches.flush();

        assert.isFalse(reading.called);
        assert.isFalse(sendStub.called);
        assert.equal(Batches.pending.length, 1);

        Tabs.ready();

        await Batches.flush();

        assert.isTrue(reading.called);
        assert.isTrue(sendStub.calledOnce);
      } finally {
        await Tabs.leave();
      }
    });

    // The first tab's restore writes a fresh pair without waiting, and sends right after: a reload
    // between the two would send the batch again under yet another pair.
    it("sends nothing until the identity written before it is stored", async () => {
      let written;

      sinon
        .stub(Durability, "replicaWritten")
        .returns(new Promise((resolve) => (written = resolve)));

      sendStub.resolves(confirmed());
      sealed(creating("t1", "first"));

      const flushing = Batches.flush();

      // Let go of whatever an assertion does: a flush left waiting keeps the sender busy for every
      // test after this one.
      try {
        await waitForEventLoop();

        assert.isFalse(sendStub.called);
        assert.equal(Batches.pending.length, 1);
      } finally {
        written();
        await flushing;
      }

      assert.isTrue(sendStub.calledOnce);
    });

    describe("when the user changes", () => {
      let written;

      beforeEach(() => {
        LocalDatabase.actorUserId = "u1";

        sinon
          .stub(Durability, "replicaWritten")
          .onFirstCall()
          .returns(new Promise((resolve) => (written = resolve)))
          .resolves();
      });

      // The server applies a batch under the user of the session that sends it.
      it("doesn't send a batch of the previous user", async () => {
        sealed(creating("t1", "first"));

        const flushing = Batches.flush();

        await waitForEventLoop();

        LocalDatabase.actorUserId = "u2";

        written();
        await flushing;

        assert.isFalse(sendStub.called);
        assert.deepStrictEqual(Batches.pending, []);
        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      it("goes on to the new user's batch behind it", async () => {
        sendStub.resolves(confirmed());
        sealed(creating("t1", "first"));

        const flushing = Batches.flush();

        await waitForEventLoop();

        LocalDatabase.actorUserId = "u2";
        const second = sealed(creating("t2", "second"));

        written();
        await flushing;

        assert.isTrue(sendStub.calledOnceWithExactly(second));
      });

      // A later batch may name a row this one created, and a frame naming the later number marks
      // everything below it as applied.
      it("sends first a lower number that arrived during the wait", async () => {
        sendStub.resolves(confirmed());

        // The lower one is a stored batch, which goes out only under the identity the store holds.
        sinon.stub(Durability, "holdsIdentity").returns(true);

        Batches.resumeFrom(5);
        sealed(creating("t2", "second"));

        const flushing = Batches.flush();

        await waitForEventLoop();

        Batches.adopt([
          {
            actorUserId: "u1",
            landed: [],
            seq: 5,
            writes: [creating("t1", "first")],
          },
        ]);

        written();
        await flushing;

        assert.deepStrictEqual(
          sendStub.getCalls().map((call) => call.args[0].seq),
          [5, 6],
        );
      });

      // The group dissolved during the wait, and the tab that kept its identity sends the batch.
      it("doesn't send a batch let go of with the user unchanged", async () => {
        // One the store holds, which the tab that kept its identity sends from there.
        sealed(creating("t1", "first")).filed = true;

        const flushing = Batches.flush();

        await waitForEventLoop();

        Batches.disown();

        written();
        await flushing;

        assert.isFalse(sendStub.called);
      });

      // The 403 is the old user's pair being refused, and the pair in use is the new user's.
      it("takes no other pair when a batch let go of while out fails", async () => {
        const persisting = sinon.stub(Durability, "persistReplica");
        const reconnecting = sinon.stub(Sse, "reconnect");
        const delaying = sinon.stub(Sse, "computeReconnectDelay");

        written();

        Replica.adopt({id: "r-stored", token: "statement-stored"});
        Replica.offer({id: "r-fresh", token: "statement-fresh"});

        let answer;

        sendStub.returns(new Promise((resolve) => (answer = resolve)));

        const batch = sealed(creating("t1", "first"));
        const flushing = Batches.flush();

        await waitForEventLoop();

        assert.isTrue(sendStub.calledOnce);

        LocalDatabase.actorUserId = "u2";
        Batches.releaseForeign("u2");

        answer({httpStatus: 403, status: "failed"});
        await flushing;

        assert.equal(Replica.id, "r-stored");
        assert.isFalse(persisting.called);
        assert.isFalse(reconnecting.called);
        assert.isFalse(delaying.called);
        assert.equal(batch.state, "pending");
      });

      // The server applied it, so it has nothing left to wait for in the store.
      it("forgets a batch let go of while out once it is answered", async () => {
        const forgetting = sinon.stub(Durability, "forgetBatch");

        written();

        let answer;

        sendStub.returns(new Promise((resolve) => (answer = resolve)));

        const batch = sealed(creating("t1", "first"));
        const flushing = Batches.flush();

        await waitForEventLoop();

        LocalDatabase.actorUserId = "u2";
        Batches.releaseForeign("u2");

        answer(confirmed());
        await flushing;

        sinon.assert.calledOnceWithExactly(
          forgetting,
          batch.seq,
          sinon.match.object,
        );

        assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      });

      // The tab moved to the new user's group as a follower while the send was out: the tab that
      // leads there sends the new user's queue, under its own pair.
      it("sends nothing more once the tab stopped sending while one was out", async () => {
        written();

        let answer;

        sendStub.returns(new Promise((resolve) => (answer = resolve)));

        sealed(creating("t1", "first"));
        const flushing = Batches.flush();

        await waitForEventLoop();

        assert.isTrue(sendStub.calledOnce);

        LocalDatabase.actorUserId = "u2";
        Batches.releaseForeign("u2");
        const second = sealed(creating("t2", "second"));
        Tabs.leader = false;

        answer(confirmed());
        await flushing;

        assert.isTrue(sendStub.calledOnce);
        assert.deepStrictEqual(Batches.pending, [second]);
        assert.equal(second.state, "pending");
      });
    });

    // The server would refuse them over a mismatch the person did not cause, and roll back what
    // they did.
    it("holds every batch while the server stopped the tab over its model", async () => {
      SyncStream.stopReason = "model_hash";

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isFalse(sendStub.called);
      assert.equal(Batches.pending.length, 1);
      assert.equal(Overlay.durability(TODO, "t1"), "applied");
    });

    // Sent now, it would go out under a pair another tab can hold.
    it("holds every batch while the tab waits for an identity", async () => {
      Replica.requestMint();

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isFalse(sendStub.called);
      assert.equal(Batches.pending.length, 1);
    });

    it("sends once the identity has arrived", async () => {
      sendStub.resolves(confirmed());

      Replica.requestMint();

      sealed(creating("t1", "first"));

      await Batches.flush();

      Replica.takeMinted({id: "r-minted", token: "statement"});

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.equal(Batches.pending.length, 0);
    });

    // The write endpoint compares the model and nothing else, so these still land.
    it("sends while the server stopped the tab over its protocol", async () => {
      SyncStream.stopReason = "protocol_version";

      sendStub.resolves(confirmed());
      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
    });

    it("stops a drain in flight behind the batch it was sending when the tab is stopped", async () => {
      sealed(creating("t1", "first"));
      sealed(creating("t2", "second"));

      sendStub.callsFake(async () => {
        SyncStream.stopReason = "model_hash";

        return confirmed();
      });

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.deepStrictEqual(
        Batches.pending.map((batch) => batch.seq),
        [2],
      );
    });

    // Held only after the store is read, so a batch another tab filed is on this tab's screen too.
    it("takes up what the store holds while holding it", async () => {
      Durability.mode = "indexeddb";
      SyncStream.stopReason = "model_hash";

      sinon.stub(Durability, "queuedBatches").resolves([
        {
          actorUserId: null,
          landed: [],
          seq: 3,
          writes: [creating("t3", "filed elsewhere")],
        },
      ]);

      await Batches.flush();

      assert.isFalse(sendStub.called);
      assert.equal(Batches.pending.length, 1);
      assert.equal(Overlay.durability(TODO, "t3"), "applied");
    });

    // The stop can arrive while the batch is still being written down.
    it("holds a batch the tab was stopped while recording", async () => {
      const batch = sealed(creating("t1", "first"));

      let record;

      batch.recorded = new Promise((resolve) => {
        record = resolve;
      });

      const flushing = Batches.flush();

      await waitForEventLoop();

      SyncStream.stopReason = "model_hash";
      record();

      await flushing;

      assert.isFalse(sendStub.called);
      assert.equal(batch.state, "pending");
    });

    // A send can reach the server before the stream says the tab is stopped, since opening the
    // stream is what wakes the queue.
    describe("a batch refused because the bundle is behind the server", () => {
      const staleBuild = () => ({
        reason: Serializer.serialize(Type.atom("stale_build")),
        status: "rejected",
      });

      let forgetting, posting;

      beforeEach(() => {
        forgetting = sinon.stub(Durability, "forgetBatch");
        posting = sinon.stub(Tabs, "post");

        sinon.stub(Logger, "debug");

        sendStub.resolves(staleBuild());
      });

      it("keeps the batch waiting, its rows on the screen and in the store", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();

        assert.equal(Batches.pending.length, 1);
        assert.equal(Batches.pending[0].state, "pending");
        assert.deepStrictEqual(Batches.rejected, []);
        assert.equal(Overlay.durability(TODO, "t1"), "applied");
        assert.isFalse(forgetting.called);
      });

      it("stops the tab over its model and tells the group", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();

        assert.equal(SyncStream.stopReason, "model_hash");

        // What puts the notice in front of the person.
        assert.isTrue(renderStub.called);

        assert.isTrue(
          posting.calledWithMatch({
            event: "sync_reload",
            frame: {reason: "model_hash"},
            kind: "frame",
          }),
        );

        assert.isFalse(posting.calledWithMatch({kind: "answered"}));
      });

      // The batch behind it would be refused the same way.
      it("sends nothing after it, and schedules no retry", async () => {
        const clock = sinon.useFakeTimers();

        try {
          sealed(creating("t1", "first"));
          sealed(creating("t2", "second"));

          await Batches.flush();

          assert.equal(clock.countTimers(), 0);

          await Batches.flush();
        } finally {
          clock.restore();
        }

        assert.isTrue(sendStub.calledOnce);
        assert.equal(Batches.pending.length, 2);
      });

      // The server checks the protocol before the model, so a deploy changing both stops the tab
      // over the protocol - which lets writes through, and the refusal is what says the model moved.
      it("holds the writes of a tab stopped over its protocol from then on", async () => {
        SyncStream.stopReason = "protocol_version";

        sealed(creating("t1", "first"));

        await Batches.flush();
        await Batches.flush();

        assert.equal(SyncStream.stopReason, "model_hash");
        assert.isTrue(sendStub.calledOnce);
        assert.equal(Batches.pending[0].state, "pending");
      });

      // What a reload onto the same model does, as a feature test sees it.
      it("leaves the batch to be sent again under its own number", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();

        SyncStream.stopReason = null;
        sendStub.resolves(confirmed());

        await Batches.flush();

        assert.isTrue(sendStub.calledTwice);
        assert.equal(sendStub.secondCall.args[0].seq, 1);
        assert.deepStrictEqual(Batches.pending, []);
      });
    });

    // The store is the order, not the messages: a batch filed by a tab that closed straight after
    // is in the queue with nothing said about it, and it ships before anything numbered above it.
    it("takes up what the store holds, before sending", async () => {
      const filed = {
        actorUserId: null,
        landed: [],
        seq: 3,
        writes: [creating("t3", "filed elsewhere")],
      };

      const reading = sinon.stub(Durability, "queuedBatches").resolves([]);

      reading.onFirstCall().resolves([filed]);

      Durability.mode = "indexeddb";
      sendStub.resolves(confirmed());

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.equal(sendStub.firstCall.args[0].seq, 3);
    });

    // The tab that filed it can run late, so its message can arrive once the batch has been read
    // from the store, sent and answered.
    it("doesn't send a batch again when its message arrives after the answer", async () => {
      Durability.mode = "indexeddb";

      const record = {
        actorUserId: null,
        landed: [],
        seq: 3,
        writes: [creating("t3", "filed elsewhere")],
      };

      sendStub.resolves(confirmed());

      Batches.adopt([record]);
      await Batches.flush();

      Batches.adopt([record]);
      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.deepStrictEqual(Batches.pending, []);
    });

    // Every tab then holds the batch before a frame or an answer about it can reach it, whether or
    // not the message from the tab that filed it ever comes.
    it("announces a batch to the group right before sending it", async () => {
      const announcing = sinon.stub(Tabs, "postNow");

      sendStub.resolves(confirmed());

      const batch = sealed(creating("t1", "first"));

      await Batches.flush();

      sinon.assert.calledOnceWithExactly(announcing, {
        kind: "sealed",
        record: batch.record(),
      });

      assert.isTrue(announcing.calledBefore(sendStub));
    });

    it("announces nothing while the tab holds its writes", async () => {
      const announcing = sinon.stub(Tabs, "postNow");

      SyncStream.stopReason = "model_hash";

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isFalse(announcing.called);
    });

    // The flush that the end of the hold starts finds the sender busy with that read, so nothing
    // else would send the queue.
    it("sends the queue when the hold ends while the queue is read", async () => {
      sendStub.resolves(confirmed());

      SyncStream.stopReason = "model_hash";

      sealed(creating("t1", "first"));

      let reads = 0;

      sinon.stub(Durability, "queuedBatches").callsFake(async () => {
        reads += 1;

        if (reads === 2) {
          SyncStream.stopReason = null;
          Batches.flush();
        }

        return [];
      });

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.deepStrictEqual(Batches.pending, []);
    });

    // A stubbed read can't tell the old loop from this one: only a real store says what a read
    // started at a given moment would have found.
    describe("with a real store", () => {
      let previousIndexedDB, previousKeyRange, sent;

      beforeEach(async () => {
        previousIndexedDB = globalThis.indexedDB;
        previousKeyRange = globalThis.IDBKeyRange;

        globalThis.indexedDB = fakeIndexedDB;
        globalThis.IDBKeyRange = FDBKeyRange;

        globalThis.Hologram.sync = {
          model: TODO_MODEL,
          modelHash: "model-a",
          protocolVersion: 7,
        };

        await Durability.reset();
        await Durability.open();

        sent = [];

        sendStub.callsFake(async (batch) => {
          sent.push(batch.seq);

          return confirmed();
        });
      });

      afterEach(async () => {
        await Durability.reset();

        if (previousIndexedDB === undefined) {
          delete globalThis.indexedDB;
        } else {
          globalThis.indexedDB = previousIndexedDB;
        }

        if (previousKeyRange === undefined) {
          delete globalThis.IDBKeyRange;
        } else {
          globalThis.IDBKeyRange = previousKeyRange;
        }
      });

      // What another tab does when it files a batch and hasn't said so yet, or never will.
      const filedElsewhere = async (id, actorUserId = null) => {
        const batch = new Batch(null);

        batch.actorUserId = actorUserId;
        batch.append(creating(id, id));

        await Durability.fileBatch(batch);

        return batch;
      };

      // Holds this tab's next filing back until the answer is called, the way a slow store does.
      const holdNextFiling = () => {
        const file = Durability.fileBatch.bind(Durability);

        let release;

        const held = new Promise((resolve) => {
          release = resolve;
        });

        const filing = sinon.stub(Durability, "fileBatch");

        filing.onFirstCall().callsFake((batch) => held.then(() => file(batch)));
        filing.callsFake(file);

        return release;
      };

      it("sends a lower batch nobody announced ahead of an announced one", async () => {
        await filedElsewhere("t1");

        const announced = await filedElsewhere("t2");

        Batches.adopt([announced.record()]);

        await Batches.flush();

        assert.deepStrictEqual(sent, [1, 2]);
      });

      it("sends a batch once when its message arrives after it went out", async () => {
        const late = await filedElsewhere("t1");
        const announced = await filedElsewhere("t2");

        Batches.adopt([announced.record()]);

        await Batches.flush();

        Batches.adopt([late.record()]);

        await Batches.flush();

        assert.deepStrictEqual(sent, [1, 2]);
      });

      // The head has no number when the sender first looks at it, and gets one above whatever
      // another tab files in the meantime.
      it("sends a batch another tab filed while the head was being filed first", async () => {
        const release = holdNextFiling();

        sealed(creating("t2", "own"));

        const flushing = Batches.flush();

        await waitForEventLoop();

        await filedElsewhere("t1");

        release();

        await flushing;

        assert.deepStrictEqual(sent, [1, 2]);
      });

      it("reads the store again for a batch closed during the read", async () => {
        const release = holdNextFiling();
        const read = Durability.queuedBatches.bind(Durability);

        const reading = sinon.stub(Durability, "queuedBatches").callsFake(read);

        reading.onFirstCall().callsFake(async (below) => {
          const records = await read(below);

          sealed(creating("t2", "own"));

          await filedElsewhere("t1");

          release();

          return records;
        });

        await Batches.flush();

        assert.deepStrictEqual(sent, [1, 2]);
      });

      // Its answer can reach this tab during the read, from the tab that led before it.
      it("reads the whole queue when the head leaves during the read", async () => {
        const head = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([head.record()]);

        const read = Durability.queuedBatches.bind(Durability);

        const reading = sinon.stub(Durability, "queuedBatches").callsFake(read);

        reading.onFirstCall().callsFake(async (below) => {
          const records = await read(below);

          Batches.settle(1, confirmed());

          await Durability.forgetBatch(1);

          return records;
        });

        await Batches.flush();

        assert.deepStrictEqual(sent, [2]);
      });

      // Guards the loop against waiting on, or spinning over, a record it will never take up.
      it("goes past another user's lower batch and leaves it in the store", async () => {
        await filedElsewhere("t1", "u2");
        await filedElsewhere("t2");

        await Batches.flush();

        assert.deepStrictEqual(sent, [2]);

        assert.deepStrictEqual(
          (await Durability.queuedBatches()).map((record) => record.seq),
          [1],
        );
      });

      // Held, the queue never drains down to it, and the batch would stay off this tab's screen.
      it("takes up a higher batch nobody announced while holding its writes", async () => {
        SyncStream.stopReason = "model_hash";

        const held = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();

        assert.deepStrictEqual(sent, []);

        assert.deepStrictEqual(
          Batches.pending.map((batch) => batch.seq),
          [1, 2],
        );
      });

      it("takes up a higher batch nobody announced when refused for its build", async () => {
        sinon.stub(Logger, "debug");

        sendStub.callsFake(async () => ({
          reason: Serializer.serialize(Type.atom("stale_build")),
          status: "rejected",
        }));

        const held = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();

        assert.deepStrictEqual(
          Batches.pending.map((batch) => batch.seq),
          [1, 2],
        );
      });

      // Nothing is about to announce it by sending it, and the tabs would show different writes.
      it("tells the group about a batch it took up while holding its writes", async () => {
        const announcing = sinon.stub(Tabs, "postNow");

        SyncStream.stopReason = "model_hash";

        const held = await filedElsewhere("t1");
        const unannounced = await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();

        sinon.assert.calledWithExactly(announcing, {
          kind: "sealed",
          record: unannounced.record(),
        });
      });

      it("announces a batch it took up while holding its writes only once", async () => {
        const announcing = sinon.stub(Tabs, "postNow");

        SyncStream.stopReason = "model_hash";

        const held = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();
        await Batches.flush();

        sinon.assert.calledOnce(announcing);
      });

      // Found by the read that stops at the head, so the read of the whole queue finds it held.
      it("tells the group about a lower batch it found while holding its writes", async () => {
        const announcing = sinon.stub(Tabs, "postNow");

        SyncStream.stopReason = "model_hash";

        const unannounced = await filedElsewhere("t1");
        const announced = await filedElsewhere("t2");

        Batches.adopt([announced.record()]);

        await Batches.flush();

        sinon.assert.calledOnceWithExactly(announcing, {
          kind: "sealed",
          record: unannounced.record(),
        });
      });

      it("tells the group about every batch it found while a send keeps failing", async () => {
        const announcing = sinon.stub(Tabs, "postNow");

        sinon.stub(console, "warn");

        sendStub.callsFake(async () => {
          throw new Error("offline");
        });

        await filedElsewhere("t1");
        await filedElsewhere("t2");

        await Batches.flush();
        await Batches.flush();

        // Each found once, and the head again before each of its two sends.
        assert.deepStrictEqual(
          announcing.args.map(([message]) => message.record.seq),
          [1, 2, 1, 1],
        );
      });

      // While the server can't be reached the head stays, so the queue doesn't drain down to it.
      it("takes up a higher batch nobody announced when a send fails", async () => {
        sinon.stub(console, "warn");

        sendStub.callsFake(async () => {
          throw new Error("offline");
        });

        const held = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();

        assert.deepStrictEqual(
          Batches.pending.map((batch) => batch.seq),
          [1, 2],
        );
      });

      it("sends a higher batch nobody announced once the queue has drained", async () => {
        const held = await filedElsewhere("t1");

        await filedElsewhere("t2");

        Batches.adopt([held.record()]);

        await Batches.flush();

        assert.deepStrictEqual(sent, [1, 2]);
      });
    });

    describe("in a tab that has lost its store", () => {
      const STORED = {id: "r-stored", token: "statement-stored"};
      const MINTED = {id: "r-minted", token: "statement-minted"};

      let reconnecting, sent, wasStarted;

      const record = (seq) => ({
        actorUserId: null,
        landed: [],
        seq,
        writes: [creating(`t${seq}`, "stored")],
      });

      // Closes a batch whose filing settles when told to, stored under the given number or not at
      // all. The store is working when it closes, and fails when the filing is told it didn't land.
      const filing = (id) => {
        Durability.mode = "indexeddb";

        let settle;

        Durability.fileBatch.callsFake(
          (batch) =>
            new Promise((resolve) => {
              settle = (seq) => {
                if (seq === null) {
                  Durability.mode = "memory";
                } else {
                  batch.seal(seq);
                }

                resolve(seq !== null);
              };
            }),
        );

        const batch = sealed(creating(id, id));

        // Whatever closes after this one files nothing, unless it asks for a filing of its own.
        Durability.fileBatch.callsFake(async () => false);

        return {batch, settle};
      };

      const mint = async () => {
        Replica.takeMinted(MINTED);

        await Batches.flush();
      };

      beforeEach(() => {
        sent = [];
        wasStarted = Sse.isStarted;
        Sse.isStarted = true;

        reconnecting = sinon.stub(Sse, "reconnect");

        sinon.stub(Durability, "fileBatch").resolves(false);

        sendStub.callsFake(async (batch) => {
          sent.push(`${Replica.id}:${batch.seq}`);

          return confirmed();
        });

        Durability.hadStore = true;

        Replica.adopt(STORED);
        Durability.noteStoredReplica(STORED);
      });

      afterEach(() => {
        Sse.isStarted = wasStarted;
        Durability.hadStore = false;
        Durability.noteStoredReplica({id: null});
      });

      // A number spent under the stored identity would be recorded nowhere, so the next load could
      // spend it again on another write.
      it("gives a new batch no number under the identity the store holds", () => {
        assert.isNull(sealed(creating("t1", "first")).seq);
      });

      // Its pair can be on its way into the store, or be what another tab wrote there.
      it("gives a new batch no number under a pair the store isn't known to hold", () => {
        Replica.adopt({id: "r-other", token: "statement-other"});

        assert.isNull(sealed(creating("t1", "first")).seq);
      });

      it("sends the stored batches under the stored identity", async () => {
        Batches.adopt([record(3), record(4)]);

        await Batches.flush();

        assert.deepStrictEqual(sent, ["r-stored:3", "r-stored:4"]);
        assert.isFalse(Replica.awaitingMint);
        assert.isFalse(reconnecting.called);
      });

      it("asks for an identity once the stored batches are out, and sends nothing new until it comes", async () => {
        Batches.adopt([record(3)]);
        sealed(creating("t5", "new"));

        await Batches.flush();

        assert.deepStrictEqual(sent, ["r-stored:3"]);
        assert.isTrue(Replica.awaitingMint);
        assert.isTrue(reconnecting.calledOnce);
        assert.equal(Batches.pending.length, 1);
      });

      it("opens no stream to ask when the page has not started one", async () => {
        Sse.isStarted = false;

        sealed(creating("t5", "new"));

        await Batches.flush();

        assert.isTrue(Replica.awaitingMint);
        assert.isFalse(reconnecting.called);
      });

      it("numbers new batches in the order made under the identity it was given", async () => {
        Batches.adopt([record(3)]);
        sealed(creating("t5", "first new"));
        sealed(creating("t6", "second new"));

        await Batches.flush();
        await mint();

        assert.deepStrictEqual(sent, [
          "r-stored:3",
          "r-minted:4",
          "r-minted:5",
        ]);
      });

      it("numbers a batch closed after the identity arrived under it", async () => {
        sealed(creating("t5", "first new"));

        await Batches.flush();
        await mint();

        sealed(creating("t6", "second new"));

        await Batches.flush();

        assert.deepStrictEqual(sent, ["r-minted:1", "r-minted:2"]);
      });

      it("sends a later filing the store took ahead of an earlier one it didn't", async () => {
        const first = filing("t1");
        const second = filing("t2");

        first.settle(null);
        await first.batch.recorded;

        const flushing = Batches.flush();

        await waitForEventLoop();

        assert.deepStrictEqual(sent, []);

        second.settle(7);

        await flushing;
        await mint();

        assert.deepStrictEqual(sent, ["r-stored:7", "r-minted:8"]);
      });

      // It goes ahead of the batch the sender was waiting on, and has to go under the stored identity.
      it("sends a filing that lands while the sender waits on an earlier one", async () => {
        const first = filing("t1");
        const second = filing("t2");

        const flushing = Batches.flush();

        await waitForEventLoop();

        first.settle(null);
        second.settle(7);

        await flushing;
        await mint();

        assert.deepStrictEqual(sent, ["r-stored:7", "r-minted:8"]);
      });

      it("sends an earlier filing that lands ahead of a batch closed once the store had gone", async () => {
        const first = filing("t1");

        Durability.mode = "memory";

        const second = sealed(creating("t2", "second"));

        assert.isNull(second.seq);

        const flushing = Batches.flush();

        await waitForEventLoop();

        first.settle(4);

        await flushing;
        await mint();

        assert.deepStrictEqual(sent, ["r-stored:4", "r-minted:5"]);
      });

      it("keeps the order made when an earlier filing fails after the store had gone", async () => {
        const first = filing("t1");

        Durability.mode = "memory";

        sealed(creating("t2", "second"));

        first.settle(null);
        await first.batch.recorded;

        await Batches.flush();
        await mint();

        assert.deepStrictEqual(sent, ["r-minted:1", "r-minted:2"]);

        assert.deepStrictEqual(
          sendStub.getCalls().map((call) => call.args[0].writes[0].id),
          ["t1", "t2"],
        );
      });

      it("keeps the order made around a filing still in flight", async () => {
        const first = filing("t1");
        const second = filing("t2");

        first.settle(null);
        await first.batch.recorded;

        const third = sealed(creating("t3", "third"));

        assert.isNull(third.seq);

        const flushing = Batches.flush();

        await waitForEventLoop();

        second.settle(6);

        await flushing;
        await mint();

        assert.deepStrictEqual(sent, [
          "r-stored:6",
          "r-minted:7",
          "r-minted:8",
        ]);

        assert.deepStrictEqual(
          sendStub.getCalls().map((call) => call.args[0].writes[0].id),
          ["t2", "t1", "t3"],
        );
      });

      // The identity can arrive while earlier filings are still in flight. A later batch may name a
      // row one of them created, so it can't take a number ahead of them.
      it("keeps the order made for a batch closed after the identity arrived", async () => {
        const first = filing("t1");
        const second = filing("t2");

        Batches.disown();
        Replica.requestMint();
        Replica.takeMinted(MINTED);

        Durability.mode = "memory";

        const third = sealed(creating("t3", "third"));

        assert.isNull(third.seq);

        first.settle(null);
        second.settle(null);

        await Promise.all([first.batch.recorded, second.batch.recorded]);
        await Batches.flush();

        assert.deepStrictEqual(sent, [
          "r-minted:1",
          "r-minted:2",
          "r-minted:3",
        ]);

        assert.deepStrictEqual(
          sendStub.getCalls().map((call) => call.args[0].writes[0].id),
          ["t1", "t2", "t3"],
        );
      });

      it("numbers a batch behind an earlier filing that fails after the identity arrived", async () => {
        const first = filing("t1");

        Batches.disown();
        Replica.requestMint();
        Replica.takeMinted(MINTED);

        Durability.mode = "memory";

        const second = sealed(creating("t2", "second"));

        first.settle(null);
        await first.batch.recorded;
        await Batches.flush();

        assert.isBelow(first.batch.seq, second.seq);
      });

      // Somebody else holds the session now, and these writes are the tab's owner's.
      it("sends nothing and asks no more once the server refused an identity", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();

        reconnecting.resetHistory();
        Replica.refuseMint();

        await Batches.flush();

        assert.deepStrictEqual(sent, []);
        assert.isFalse(Replica.awaitingMint);
        assert.isFalse(reconnecting.called);
        assert.equal(Batches.pending.length, 1);
      });

      it("holds a batch numbered in a page that never had a store once refused", async () => {
        Durability.hadStore = false;
        Replica.requestMint();

        assert.isNotNull(sealed(creating("t1", "first")).seq);

        Replica.refuseMint();

        await Batches.flush();

        assert.deepStrictEqual(sent, []);
      });

      // Under another identity the server has no record of it, and would apply it again.
      it("lets a stored batch go rather than send it under an identity the store doesn't hold", async () => {
        Batches.adopt([record(3)]);
        Replica.adopt({id: "r-other", token: "statement-other"});

        await Batches.flush();

        assert.deepStrictEqual(sent, []);
        assert.deepStrictEqual(Batches.pending, []);
      });

      it("keeps a batch only this tab holds when it lets the stored ones go", async () => {
        Replica.adopt({id: "r-other", token: "statement-other"});

        Batches.adopt([record(3)]);
        sealed(creating("t5", "new"));

        await Batches.flush();
        await mint();

        assert.deepStrictEqual(sent, ["r-minted:4"]);
      });

      // The first send may have landed, and a second under a new identity would apply it again.
      it("lets a stored batch go on a 403 rather than move it to another identity", async () => {
        Replica.offer({id: "r-fresh", token: "statement-fresh"});

        sendStub.resetBehavior();
        sendStub.resolves({httpStatus: 403, status: "failed"});

        Batches.adopt([record(3)]);

        await Batches.flush();

        assert.isTrue(sendStub.calledOnce);
        assert.equal(Replica.id, "r-stored");
        assert.deepStrictEqual(Batches.pending, []);
      });
    });

    it("tells the group what the server answered", async () => {
      const posting = sinon.stub(Tabs, "post");
      const answer = confirmed();

      sendStub.resolves(answer);
      sealed(creating("t1", "first"));

      await Batches.flush();

      // Not the only thing this tab told the group - sealing the batch told it too.
      assert.isTrue(
        posting.calledWithExactly({answer, kind: "answered", seq: 1}),
      );
    });

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

    // A number handed out but never stored is one the next page load hands out again, and the
    // server answers the batch carrying it with the verdict the FIRST one got. The wait sits
    // between the seal and the send, where nobody is looking at it - the rows are already on
    // screen and the action's render has already happened.
    it("waits for the number to be recorded before sending", async () => {
      let record;

      const recording = new Promise((resolve) => {
        record = resolve;
      });

      sinon.stub(Durability, "fileBatch").returns(recording);
      sendStub.resolves(confirmed());

      sealed(creating("t1", "first"));

      const flushing = Batches.flush();

      await waitForEventLoop();

      assert.isFalse(sendStub.called);

      record();

      await flushing;

      assert.isTrue(sendStub.calledOnce);
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

    // The value lost the merge, and the answer says what stands in its place - so the column goes
    // straight from what this client wrote to the winning value, without the row's older value
    // showing in between while the frame is still on its way.
    it("files what a lost column kept", async () => {
      LocalDatabase.putRow(TODO, {
        done: false,
        id: "t1",
        title: "before either of us",
        $revisions: {title: 99},
      });

      sealed({
        based_on: {title: 99},
        data: {title: "mine"},
        id: "t1",
        op: "update",
        stamp: STAMP,
        type: TODO,
      });

      sendStub.resolves(
        confirmed(
          {0: {title: "mine"}},
          {0: {title: "theirs", $revisions: {title: STAMP + 1}}},
        ),
      );

      await Batches.flush();

      const base = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(base.title, "theirs");
      assert.equal(base.$revisions.title, STAMP + 1);
    });

    // The client's own copy is already gone - the fold took it away when the delete was made - so
    // the row the answer describes is what puts it back. A patch for a row this client no longer
    // holds is passed over, which is what makes the loss permanent otherwise.
    it("keeps a row whose delete lost", async () => {
      LocalDatabase.putRow(TODO, {
        done: false,
        id: "t1",
        title: "held",
        $revisions: {done: 99, title: 99},
      });

      sealed({
        based_on: {done: 99, title: 99},
        id: "t1",
        op: "delete",
        stamp: STAMP,
        type: TODO,
      });

      sendStub.resolves(
        confirmed(
          {0: {done: null, title: null}},
          {
            0: {
              done: false,
              id: "t1",
              title: "theirs",
              $revisions: {done: 99, title: STAMP + 1},
            },
          },
        ),
      );

      await Batches.flush();

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "theirs");
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
        reason: Serializer.serialize(Type.atom("nope")),
        status: "rejected",
        write: 0,
      });

      await Batches.flush();

      assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      assert.deepStrictEqual(Batches.pending, []);
      assert.equal(Batches.rejected.length, 1);
      assert.equal(Batches.rejected[0].seq, 1);
      assert.deepStrictEqual(Batches.rejected[0].reason, Type.atom("nope"));
      assert.equal(Batches.rejected[0].write, 0);
      assert.equal(Batches.rejected[0].state, "rejected");
    });

    // The answer arrives as the server spelled it, so the term a refusal carries is read here -
    // the one place anything needs it rather than the JSON it travelled as.
    it("reads the term a refusal's reason was serialized as", async () => {
      sealed(creating("t1", "first"));

      sendStub.resolves({
        reason: Serializer.serialize(
          Type.map([[Type.atom("slug"), Type.list([Type.atom("unique")])]]),
        ),
        status: "rejected",
        write: 0,
      });

      await Batches.flush();

      assert.deepStrictEqual(
        Batches.rejected[0].reason,
        Type.map([[Type.atom("slug"), Type.list([Type.atom("unique")])]]),
      );
    });

    it("forgets a confirmed batch", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");

      sealed(creating("t1", "first"));
      sendStub.resolves(confirmed());

      await Batches.flush();

      sinon.assert.calledOnceWithExactly(forgetting, 1, sinon.match.object);
    });

    // The tab can follow a sign-in while the batch is out.
    it("forgets a batch under the identity it was sent under", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");
      const sentUnder = {holdsIdentity: true, owner: null, replicaId: "r-sent"};
      const signedIn = {holdsIdentity: true, owner: "u2", replicaId: "r-new"};
      let current = sentUnder;
      let answer;

      sinon.stub(Durability, "sentUnder").callsFake(() => current);
      sendStub.returns(new Promise((resolve) => (answer = resolve)));
      sealed(creating("t1", "first"));

      const flushing = Batches.flush();

      await waitForEventLoop();

      current = signedIn;
      answer(confirmed());
      await flushing;

      sinon.assert.calledOnceWithExactly(forgetting, 1, sentUnder);
    });

    // Its number was never recorded, so a batch the store holds under it can be another tab's.
    it("forgets and tells nothing of a batch the store never got", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");
      const posting = sinon.stub(Tabs, "post");

      const originalMode = Durability.mode;

      const batch = sealed(creating("t1", "first"));
      batch.filed = false;
      sendStub.resolves(confirmed());

      try {
        Durability.mode = "indexeddb";

        await Batches.flush();
      } finally {
        Durability.mode = originalMode;
      }

      assert.deepStrictEqual(Batches.pending, []);
      sinon.assert.notCalled(forgetting);
      sinon.assert.neverCalledWithMatch(posting, {kind: "answered"});
    });

    // The answer is withheld for it, so a tab that took it up would keep it on screen.
    it("announces no batch the store never got as it sends it", async () => {
      const announcing = sinon.stub(Tabs, "postNow");

      const originalMode = Durability.mode;

      const batch = sealed(creating("t1", "first"));
      batch.filed = false;
      sendStub.resolves(confirmed());

      try {
        Durability.mode = "indexeddb";

        await Batches.flush();
      } finally {
        Durability.mode = originalMode;
      }

      sinon.assert.calledOnce(sendStub);
      sinon.assert.neverCalledWithMatch(announcing, {kind: "sealed"});
    });

    // Refused for the writes or refused for the build, it is answered either way - and a batch
    // kept for a resend would come back on a later page load as a write the user watched fail.
    it("forgets a refused batch", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");

      sealed(creating("t1", "first"));

      sendStub.resolves({
        reason: Serializer.serialize(Type.atom("nope")),
        status: "rejected",
        write: 0,
      });

      await Batches.flush();

      sinon.assert.calledOnceWithExactly(forgetting, 1, sinon.match.object);
    });

    // A delete that fails on the spot ends the group, and a tab that never heard would resend it.
    it("tells the group about the answer before forgetting the batch", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");
      const posting = sinon.stub(Tabs, "post");

      sealed(creating("t1", "first"));
      sendStub.resolves(confirmed());

      await Batches.flush();

      sinon.assert.callOrder(
        posting.withArgs(sinon.match({kind: "answered", seq: 1})),
        forgetting,
      );
    });

    it("forgets nothing about a batch nobody answered", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");

      sealed(creating("t1", "first"));
      sendStub.resolves({httpStatus: 502, status: "failed"});

      await Batches.flush();

      assert.isFalse(forgetting.called);
    });

    describe("the retry", () => {
      let timers;

      beforeEach(() => {
        timers = sinon.useFakeTimers();
      });

      afterEach(() => {
        timers.restore();
      });

      // The stream is up so no reconnect is coming, and the user is idle so no action is - without
      // this a batch sits unsent while the page looks perfectly healthy.
      it("goes again on its own, on the stream's backoff", async () => {
        sinon.stub(Sse, "computeReconnectDelay").returns(250);

        sealed(creating("t1", "first"));

        sendStub.onFirstCall().resolves({httpStatus: 503, status: "failed"});
        sendStub.onSecondCall().resolves(confirmed());

        await Batches.flush();

        sinon.assert.calledOnce(sendStub);

        await timers.tickAsync(249);

        sinon.assert.calledOnce(sendStub);

        await timers.tickAsync(1);

        sinon.assert.calledTwice(sendStub);
        assert.deepStrictEqual(Batches.pending, []);
      });

      // One tick per retry rather than one tick for all: a retry scheduled DURING a tick, at the
      // same instant, waits for the next one - so each tick is one try, and the attempt count is
      // read after each.
      it("backs off further with every unanswered try", async () => {
        const delay = sinon.stub(Sse, "computeReconnectDelay").returns(1);

        sealed(creating("t1", "first"));
        sendStub.resolves({httpStatus: 503, status: "failed"});

        await Batches.flush();

        assert.deepStrictEqual(
          delay.getCalls().map((call) => call.args[0]),
          [1],
        );

        await timers.tickAsync(1);

        assert.deepStrictEqual(
          delay.getCalls().map((call) => call.args[0]),
          [1, 2],
        );

        await timers.tickAsync(1);

        assert.deepStrictEqual(
          delay.getCalls().map((call) => call.args[0]),
          [1, 2, 3],
        );
      });

      // A server that is answering again has earned the short delay, whatever it took to get there.
      it("starts the backoff over once a batch is answered", async () => {
        const delay = sinon.stub(Sse, "computeReconnectDelay").returns(1);

        sealed(creating("t1", "first"));
        sealed(creating("t2", "second"));

        sendStub.onFirstCall().resolves({httpStatus: 503, status: "failed"});
        sendStub.onSecondCall().resolves(confirmed());
        sendStub.onThirdCall().resolves({httpStatus: 503, status: "failed"});

        // The first try fails and schedules attempt 1. The retry answers batch 1 and then fails
        // batch 2 in the same run - so the count was reset between the two, and the second
        // schedule asks for attempt 1 again rather than 2.
        await Batches.flush();
        await timers.tickAsync(1);

        sinon.assert.calledThrice(sendStub);

        assert.deepStrictEqual(
          delay.getCalls().map((call) => call.args[0]),
          [1, 1],
        );
      });

      // A second failure replaces the first retry rather than adding to it. The delays differ per
      // attempt so the two are told apart: a first-attempt timer left standing would fire at 100
      // and send, where the replacement fires at 200.
      it("schedules one retry at a time", async () => {
        sinon
          .stub(Sse, "computeReconnectDelay")
          .callsFake((attempts) => attempts * 100);

        sealed(creating("t1", "first"));
        sendStub.resolves({httpStatus: 503, status: "failed"});

        await Batches.flush();
        await Batches.flush();

        sinon.assert.calledTwice(sendStub);

        await timers.tickAsync(150);

        sinon.assert.calledTwice(sendStub);

        await timers.tickAsync(50);

        sinon.assert.calledThrice(sendStub);
      });

      it("is not scheduled for a batch that was answered", async () => {
        const delay = sinon.stub(Sse, "computeReconnectDelay").returns(250);

        sealed(creating("t1", "first"));

        sendStub.resolves({
          reason: Serializer.serialize(Type.atom("nope")),
          status: "rejected",
          write: 0,
        });

        await Batches.flush();
        await timers.tickAsync(250);

        sinon.assert.calledOnce(sendStub);
        assert.isFalse(delay.called);
      });
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

    // The 403 is about the identity, never the writes - so it is the one no-verdict answer worth
    // doing something about rather than waiting out.
    it("presents the page's pair and sends the batch again after a 403", async () => {
      const persisting = sinon.stub(Durability, "persistReplica");
      const reconnecting = sinon.stub(Sse, "reconnect");

      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.offer({id: "r-fresh", token: "statement-fresh"});

      sendStub.onFirstCall().resolves({httpStatus: 403, status: "failed"});
      sendStub.onSecondCall().resolves(confirmed());

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.equal(Replica.id, "r-fresh");

      assert.isTrue(
        persisting.calledOnceWithExactly({
          id: "r-fresh",
          token: "statement-fresh",
        }),
      );

      assert.isTrue(reconnecting.calledOnce);
      assert.equal(sendStub.callCount, 2);
      assert.equal(sendStub.secondCall.args[0].seq, 1);
      assert.deepStrictEqual(Batches.pending, []);
    });

    // Every tab of this browser presents the pair that was just refused, and would each find that
    // out the hard way. One switch, told once.
    it("tells the group the identity it switched to after a 403", async () => {
      const telling = sinon.stub(Tabs, "postState");

      sinon.stub(Durability, "persistReplica");
      sinon.stub(Sse, "reconnect");

      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.offer({id: "r-fresh", token: "statement-fresh"});

      sendStub.onFirstCall().resolves({httpStatus: 403, status: "failed"});
      sendStub.onSecondCall().resolves(confirmed());

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isTrue(telling.calledOnce);
    });

    // The identity gets the discipline the number gets: nothing goes out under a pair that is not
    // recorded, or a reload landing in between would take up the refused one again.
    it("waits for the new pair to be recorded before sending again", async () => {
      let record;

      const recording = new Promise((resolve) => {
        record = resolve;
      });

      sinon.stub(Durability, "persistReplica").returns(recording);
      sinon.stub(Sse, "reconnect");

      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.offer({id: "r-fresh", token: "statement-fresh"});

      sendStub.onFirstCall().resolves({httpStatus: 403, status: "failed"});
      sendStub.onSecondCall().resolves(confirmed());

      sealed(creating("t1", "first"));

      const flushing = Batches.flush();

      await waitForEventLoop();

      assert.equal(sendStub.callCount, 1);

      record();

      await flushing;

      assert.equal(sendStub.callCount, 2);
    });

    // The page's own pair was the one refused, so there is nowhere left to go - which is what a
    // session that changed after this page loaded looks like.
    it("leaves the batch pending after a 403 it has no other pair to answer", async () => {
      sinon.stub(Sse, "reconnect");

      Replica.offer({id: "r-fresh", token: "statement-fresh"});

      sendStub.resolves({httpStatus: 403, status: "failed"});

      const batch = sealed(creating("t1", "first"));

      await Batches.flush();

      assert.equal(sendStub.callCount, 1);
      assert.equal(batch.state, "pending");
      assert.deepStrictEqual(Batches.pending, [batch]);
    });

    // Every handshake hands the tab a new pair, so a refusal no pair cures would otherwise switch
    // and send again for as long as it lasts, with no pause.
    describe("a 403 of a batch sent under the pair it switched to", () => {
      let delaying, reconnecting, timers;

      beforeEach(() => {
        timers = sinon.useFakeTimers();

        sinon.stub(Durability, "persistReplica");

        delaying = sinon.stub(Sse, "computeReconnectDelay").returns(60_000);

        reconnecting = sinon.stub(Sse, "reconnect").callsFake(() => {
          Replica.offer({id: "r-next", token: "statement-next"});
        });

        Replica.adopt({id: "r-stored", token: "statement-stored"});
        Replica.offer({id: "r-fresh", token: "statement-fresh"});

        sendStub.resolves({httpStatus: 403, status: "failed"});
      });

      it("waits out the backoff", async () => {
        const batch = sealed(creating("t1", "first"));

        await Batches.flush();

        assert.equal(sendStub.callCount, 2);
        assert.isTrue(reconnecting.calledOnce);
        assert.equal(Replica.id, "r-fresh");
        assert.equal(batch.state, "pending");
        assert.isTrue(delaying.calledOnce);
      });

      afterEach(() => {
        timers.restore();
      });

      // The new stream's opening flushes the queue, and would switch again with no pause.
      it("switches no pair on a flush before the backoff ends", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();
        await Batches.flush();

        assert.equal(Replica.id, "r-fresh");
        assert.isTrue(reconnecting.calledOnce);
      });

      // The user's actions flush the queue more often than the backoff lasts.
      it("waits for the retry already set, through flushes that come before it", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();
        await timers.tickAsync(30_000);
        await Batches.flush();
        await timers.tickAsync(30_000);

        assert.equal(Replica.id, "r-next");
      });

      // A later refusal can be a session that changed again, which the newest pair does cure.
      it("may switch again once the backoff ends", async () => {
        sealed(creating("t1", "first"));

        await Batches.flush();
        await timers.tickAsync(60_000);

        assert.equal(Replica.id, "r-next");
        assert.isTrue(reconnecting.calledTwice);
      });

      // A retry an earlier batch left ends sooner than the backoff the switch is held to.
      it("waits out its own backoff, not one an earlier batch left", async () => {
        sendStub.resolves({httpStatus: 503, status: "failed"});
        sealed(creating("t1", "first"));

        await Batches.flush();
        await timers.tickAsync(50_000);

        // The call history goes too, so the first call configured is the next one.
        sendStub.reset();
        sendStub.onFirstCall().resolves(confirmed());
        sendStub.resolves({httpStatus: 403, status: "failed"});
        const second = sealed(creating("t2", "second"));

        await Batches.flush();

        // The first one's retry, then the second one under each pair. The first is settled.
        assert.equal(sendStub.callCount, 3);
        assert.deepStrictEqual(Batches.pending, [second]);
        assert.equal(Replica.id, "r-fresh");

        await timers.tickAsync(10_000);

        assert.equal(Replica.id, "r-fresh");
        assert.isTrue(reconnecting.calledOnce);
      });

      // Its owner signs in again in another session, which the newest pair can cure.
      it("may switch again once it comes back from being put aside", async () => {
        const batch = sealed(creating("t1", "first"));

        await Batches.flush();

        Batches.releaseForeign("u2");

        await timers.tickAsync(60_000);

        Batches.releaseForeign(batch.actorUserId);

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.isFalse(batch.switchedPair);
      });
    });

    // The pair's twin: a dropped connection says nothing about who this client is, so what it is
    // holding stays. Spending the page's fresh pair on a network blip would leave nothing to
    // answer a real refusal with, and would restart the stream for no reason.
    it("leaves the identity alone when a send fails for any other reason", async () => {
      const reconnecting = sinon.stub(Sse, "reconnect");

      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.offer({id: "r-fresh", token: "statement-fresh"});

      sendStub.resolves({httpStatus: 503, status: "failed"});

      const batch = sealed(creating("t1", "first"));

      await Batches.flush();

      assert.equal(Replica.id, "r-stored");
      assert.isFalse(reconnecting.called);
      assert.equal(sendStub.callCount, 1);
      assert.equal(batch.state, "pending");
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

  describe("land()", () => {
    const sealed = (...writes) => {
      Batches.open("todos");

      for (const write of writes) {
        Batches.current().append(write);
      }

      return Batches.close();
    };

    // What a reload would otherwise cost: a batch whose frame arrived and whose ANSWER was lost is
    // taken up again by the next page load and sent again, answered from the server's record, and
    // promoted - and a moved counter promoted onto a base that already holds the move counts it
    // twice, for good, since the server has nothing further to say about a row nobody has touched.
    it("writes the marks down when a frame lands a write", () => {
      const writing = sinon.stub(Durability, "persistLanded");
      const batch = sealed(write("t1"));

      Batches.land(1, new Set([`${TODO} t1`]));

      assert.isTrue(writing.calledOnceWithExactly(batch));
    });

    it("writes nothing down when the frame marks nothing new", () => {
      const writing = sinon.stub(Durability, "persistLanded");

      sealed(write("t1"));

      Batches.land(1, new Set([`${TODO} t1`]));
      Batches.land(1, new Set([`${TODO} t1`]));

      assert.isTrue(writing.calledOnce);
    });

    // Nothing the server says can be about a batch it has never been sent - and a number it does
    // not have yet is below every number, which is what makes this worth spelling out.
    it("passes over a batch that has no number yet", () => {
      const writing = sinon.stub(Durability, "persistLanded");

      Durability.mode = "indexeddb";

      sinon.stub(Durability, "fileBatch").returns(new Promise(() => {}));

      const batch = sealed(write("t1"));

      Batches.land(5, new Set([`${TODO} t1`]));

      assert.isNull(batch.seq);
      assert.isFalse(batch.isLanded(0));
      assert.isFalse(writing.called);
    });

    it("writes nothing down for a batch above the number", () => {
      const writing = sinon.stub(Durability, "persistLanded");

      sealed(write("t1"));
      sealed(write("t2"));

      Batches.land(1, new Set([`${TODO} t1`, `${TODO} t2`]));

      assert.isTrue(writing.calledOnce);
    });

    // Up to the number and no further, in one call: a batch the server has applied stops being
    // folded, and the one after it goes on showing, because nothing has been said about it yet.
    it("marks the writes of the batches the server has applied, and no others", () => {
      const first = sealed(write("t1"));
      const second = sealed(write("t2"));

      Batches.land(1, new Set([`${TODO} t1`, `${TODO} t2`]));

      assert.isTrue(first.isLanded(0));
      assert.isFalse(second.isLanded(0));
    });

    // A batch whose answer has not come back yet is still in the queue, and its effects can reach
    // the stream before the answer does - which is the ordering this whole mechanism exists for.
    it("marks a batch that is still in flight", () => {
      const batch = sealed(write("t1"));
      batch.mark("sending");

      Batches.land(1, new Set([`${TODO} t1`]));

      assert.isTrue(batch.isLanded(0));
    });

    // Nothing of the open batch has been sent, so nothing of it can have been applied.
    it("leaves the batch the action is still writing alone", () => {
      Batches.open("todos");
      Batches.current().append(write("t1"));

      Batches.land(9, new Set([`${TODO} t1`]));

      assert.isFalse(Batches.current().isLanded(0));
    });

    it("marks nothing when the frame names no number", () => {
      const batch = sealed(write("t1"));

      Batches.land(null, new Set([`${TODO} t1`]));

      assert.isFalse(batch.isLanded(0));
    });

    // What a bundle talking to a server that predates the field reads off a frame.
    it("marks nothing when the frame names no number at all", () => {
      const batch = sealed(write("t1"));

      Batches.land(undefined, new Set([`${TODO} t1`]));

      assert.isFalse(batch.isLanded(0));
    });
  });

  describe("landUnsent()", () => {
    const STAMP = 1_798_246_400_125_952;

    const create = (id, type = TODO) => ({
      data: {title: "created here"},
      id,
      op: "create",
      stamp: STAMP,
      type,
    });

    const edge = (id, targetId) => ({
      id,
      op: "add_relationship",
      relationship: "tags",
      stamp: STAMP,
      target_id: targetId,
      type: TODO,
    });

    const queued = (seq, ...writes) => {
      Batches.adopt([{actorUserId: null, landed: [], seq, writes}]);

      return Batches.pending.find((batch) => batch.seq === seq);
    };

    const confirmed = {dropped: {}, kept: {}, status: "confirmed"};

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          ...TODO_MODEL,
          [TAG]: {
            attributes: {
              created_at: "datetime",
              id: "uuid",
              title: "string",
              updated_at: "datetime",
            },
            constraints: {},
            defaults: {},
            enumValues: {},
            frameworkAttributes: [],
            relationships: {},
            serverOnly: [],
          },
        },
      };

      LocalDatabase.reset();
      Model.reset();

      sinon.stub(SyncStream, "scheduleRender");
    });

    afterEach(() => {
      LocalDatabase.reset();
    });

    it("takes a create the fill did not send off the screen", () => {
      queued(3, create("t1"));

      assert.isNotNull(LocalDatabase.getRow(TODO, "t1"));

      Batches.landUnsent([TODO], 3);

      assert.isNull(LocalDatabase.getRow(TODO, "t1"));
    });

    it("keeps the answer from filing a create the fill did not send", () => {
      queued(3, create("t1"));

      Batches.landUnsent([TODO], 3);
      Batches.settle(3, confirmed);

      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    // A grant the browser made is answered with the row the server stored, which the answer would
    // otherwise file whole.
    it("keeps an answer carrying the whole row from filing it", () => {
      queued(3, create("t1"));

      Batches.landUnsent([TODO], 3);

      Batches.settle(3, {
        dropped: {},
        kept: {0: {id: "t1", title: "stored", $revisions: {}}},
        status: "confirmed",
      });

      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("passes over the batch's other writes naming the row", () => {
      const batch = queued(3, create("t1"), edge("t1", "g1"));

      Batches.landUnsent([TODO], 3);

      assert.isTrue(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));
    });

    it("passes over a later batch's writes naming the row, up to the number", () => {
      queued(3, create("t1"));

      const later = queued(4, edge("t1", "g1"));
      const above = queued(5, edge("t1", "g2"));

      Batches.landUnsent([TODO], 4);

      assert.isTrue(later.isLanded(0));
      assert.isFalse(above.isLanded(0));
    });

    // Filed, the edge would leave a held row's set naming a row this client doesn't hold.
    it("passes over an edge pointing at the row", () => {
      const batch = queued(3, create("g1", TAG), edge("t1", "g1"));

      Batches.landUnsent([TAG], 3);
      Batches.settle(3, confirmed);

      assert.isTrue(batch.isLanded(1));
      assert.deepStrictEqual(
        Array.from(LocalDatabase.baseTargetIds(TODO, "tags", "t1")),
        [],
      );
    });

    it("leaves an edge pointing at another row", () => {
      const batch = queued(3, create("g1", TAG), edge("t1", "g2"));

      Batches.landUnsent([TAG], 3);

      assert.isFalse(batch.isLanded(1));
    });

    it("leaves an edge whose target shares its id with a row of another type", () => {
      const batch = queued(3, create("g1"), edge("t1", "g1"));

      Batches.landUnsent([TODO], 3);

      assert.isTrue(batch.isLanded(0));
      assert.isFalse(batch.isLanded(1));
    });

    // A frame delivered the row and it has left since, so the create is landed and the row is gone,
    // and the edge the answer is about to file would name it.
    it("passes over an edge pointing at a row a frame landed that has left since", () => {
      const batch = queued(3, create("g1", TAG), edge("t1", "g1"));

      batch.land(new Set([`${TAG} g1`]));

      Batches.landUnsent([TAG], 3);

      assert.isTrue(batch.isLanded(1));
    });

    // Committed after the type was read, so its session judges it.
    it("leaves a batch above the number", () => {
      const batch = queued(4, create("t1"));

      Batches.landUnsent([TODO], 3);
      Batches.settle(4, confirmed);

      assert.isFalse(batch.isLanded(0));
      assert.isNotNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("makes no claim when the marker names no number", () => {
      const batch = queued(3, create("t1"));

      Batches.landUnsent([TODO], null);

      assert.isFalse(batch.isLanded(0));
    });

    // What a bundle talking to a server that predates the field reads off a marker.
    it("makes no claim when the marker names no number at all", () => {
      const batch = queued(3, create("t1"));

      Batches.landUnsent([TODO], undefined);

      assert.isFalse(batch.isLanded(0));
    });

    // Each type is read at its own moment, so its number says nothing about another type's rows.
    it("leaves a create of a type the marker doesn't name", () => {
      const batch = queued(3, create("t1"), create("g1", TAG));

      Batches.landUnsent([TAG], 3);

      assert.isFalse(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));
    });

    it("passes over a batch that has no number yet", () => {
      const writing = sinon.stub(Durability, "persistLanded");

      Durability.mode = "indexeddb";

      sinon.stub(Durability, "fileBatch").returns(new Promise(() => {}));

      Batches.open("todos");
      Batches.current().append(create("t1"));

      const batch = Batches.close();

      Batches.landUnsent([TODO], 5);

      assert.isNull(batch.seq);
      assert.isFalse(batch.isLanded(0));
      assert.isFalse(writing.called);
    });

    it("leaves a create whose row the fill delivered", () => {
      const batch = queued(3, create("t1"));

      LocalDatabase.putRow(TODO, {id: "t1", title: "from the fill"});

      Batches.landUnsent([TODO], 3);

      assert.isFalse(batch.isLanded(0));
    });

    // The marker is said once, so a page load sending the batch again has only the marks to go by.
    it("keeps a resent batch from filing the row after a reload", () => {
      const batch = queued(3, create("t1"));

      Batches.landUnsent([TODO], 3);

      const record = batch.record();

      Batches.reset();
      Batches.adopt([record]);
      Batches.settle(3, confirmed);

      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("writes down only the batches whose marks moved", () => {
      const writing = sinon.stub(Durability, "persistLanded");
      const batch = queued(3, create("t1"));

      queued(4, create("g1", TAG));

      Batches.landUnsent([TODO], 4);

      assert.isTrue(writing.calledOnceWithExactly(batch));
    });

    it("writes nothing down when told again", () => {
      const writing = sinon.stub(Durability, "persistLanded");

      queued(3, create("t1"));

      Batches.landUnsent([TODO], 3);
      Batches.landUnsent([TODO], 3);

      assert.isTrue(writing.calledOnce);
    });
  });

  describe("the queue reads", () => {
    const write = (id) => ({id, op: "delete", stamp: 1, type: TODO});

    const queued = (id) => {
      Batches.open("todos");
      Batches.current().append(write(id));

      return Batches.close();
    };

    it("counts nothing when nothing is pending", () => {
      assert.equal(Batches.pendingCount(), 0);
      assert.isNull(Batches.oldestPendingSeq());
      assert.deepStrictEqual(Batches.rejectedSummaries(), []);
    });

    it("counts the batches waiting to ship", () => {
      queued("t1");
      queued("t2");

      assert.equal(Batches.pendingCount(), 2);
    });

    it("names the oldest waiting batch by its number", () => {
      queued("t1");
      queued("t2");

      assert.equal(Batches.oldestPendingSeq(), 1);

      Batches.pending.shift();

      assert.equal(Batches.oldestPendingSeq(), 2);
    });

    // Inspected rather than boxed, so a devtools panel and a browser-driven test can both take it
    // through JSON.
    it("reads a refusal back as something a person can read", () => {
      const batch = queued("t1");

      batch.reason = Type.map([
        [Type.atom("slug"), Type.list([Type.atom("unique")])],
      ]);

      batch.write = 0;
      Batches.rejected.push(batch);

      assert.deepStrictEqual(Batches.rejectedSummaries(), [
        {
          reason: "%{slug: [:unique]}",
          rows: [`${TODO} t1`],
          seq: 1,
          write: 0,
        },
      ]);
    });
  });

  describe("settle()", () => {
    const STAMP = 1_798_246_400_125_952;

    const queued = (seq, id) => {
      const record = {
        actorUserId: null,
        landed: [],
        seq,
        writes: [
          {
            data: {done: false, title: "made elsewhere"},
            id,
            op: "create",
            stamp: STAMP,
            type: TODO,
          },
        ],
      };

      Batches.adopt([record]);

      return Batches.pending.find((batch) => batch.seq === seq);
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.reset();
      Model.reset();

      sinon.stub(SyncStream, "scheduleRender");
    });

    afterEach(() => {
      LocalDatabase.reset();
    });

    it("promotes a confirmed batch into the base", () => {
      queued(3, "t1");

      Batches.settle(3, {dropped: {}, kept: {}, status: "confirmed"});

      assert.deepStrictEqual(Batches.pending, []);
      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "made elsewhere");
    });

    it("takes a refused batch's rows away and keeps what the server said", () => {
      queued(3, "t1");

      Batches.settle(3, {
        reason: Serializer.serialize(Type.atom("nope")),
        status: "rejected",
        write: 0,
      });

      assert.deepStrictEqual(Batches.pending, []);
      assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      assert.equal(Batches.rejected.length, 1);
      assert.deepStrictEqual(Batches.rejected[0].reason, Type.atom("nope"));
    });

    it("repaints for what the answer changed", () => {
      queued(3, "t1");

      Batches.settle(3, {dropped: {}, kept: {}, status: "confirmed"});

      assert.isTrue(SyncStream.scheduleRender.called);
    });

    describe("whether a fill is pending", () => {
      const fillPending = () => {
        const promoting = sinon.stub(Overlay, "promote");

        queued(3, "t1");

        Batches.settle(3, {dropped: {}, kept: {}, status: "confirmed"});

        return promoting.firstCall.args[2].fillPending;
      };

      afterEach(() => {
        SyncStream.syncCursor = null;
      });

      it("is true for a client with no place that isn't complete", () => {
        SyncStream.syncCursor = null;

        assert.isTrue(fillPending());
      });

      it("is false for a client coming back with a place", () => {
        SyncStream.syncCursor = "Nzc4LjA";

        assert.isFalse(fillPending());
      });

      // A node of an older build can end a fill with no place on its marker.
      it("is false for a client told it holds everything", () => {
        SyncStream.syncCursor = null;
        LocalDatabase.markAllSynced();

        assert.isFalse(fillPending());
      });
    });

    // A tab that never took the batch up, or has settled it already, has nothing to do - and every
    // tab of the browser is told every answer.
    it("passes over a number it does not hold", () => {
      const batch = queued(3, "t1");

      Batches.settle(5, {dropped: {}, kept: {}, status: "confirmed"});

      assert.deepStrictEqual(Batches.pending, [batch]);
      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("settles the batch the number names, not the one at the head", () => {
      const first = queued(3, "t1");

      queued(5, "t2");

      Batches.settle(5, {dropped: {}, kept: {}, status: "confirmed"});

      assert.deepStrictEqual(Batches.pending, [first]);
      assert.equal(LocalDatabase.baseRow(TODO, "t2").title, "made elsewhere");
    });
  });

  describe("carryAcrossSuspension()", () => {
    const ids = (batch) => batch.writes.map((write) => write.id);

    it("leaves nothing running while the action is away", () => {
      Batches.open("todos");
      Batches.carryAcrossSuspension(Promise.resolve());

      assert.isNull(Batches.current());
    });

    it("puts the action's own batch back when it resumes", async () => {
      const batch = Batches.open("todos");

      await Batches.carryAcrossSuspension(Promise.resolve());

      assert.strictEqual(Batches.current(), batch);
    });

    it("answers what the awaited promise answered", async () => {
      Batches.open("todos");

      const value = await Batches.carryAcrossSuspension(Promise.resolve("x"));

      assert.equal(value, "x");
    });

    // The whole point of the round trip: an action that comes back from an await must write to,
    // and close, the batch it opened - not whichever action ran while it was gone.
    it("keeps the writes of two interleaved actions in their own batches", async () => {
      let resumeFirst, resumeSecond;

      const firstAwaited = new Promise((resolve) => (resumeFirst = resolve));
      const secondAwaited = new Promise((resolve) => (resumeSecond = resolve));

      const firstBatch = Batches.open("first");
      const firstSuspension = Batches.carryAcrossSuspension(firstAwaited);

      const secondBatch = Batches.open("second");
      const secondSuspension = Batches.carryAcrossSuspension(secondAwaited);

      // The first action comes back while the second is still away, which is the order a stack of
      // open batches gets wrong: its top is the second one.
      resumeFirst();
      await firstSuspension;
      wrote("t1");

      assert.strictEqual(Batches.close(), firstBatch);

      resumeSecond();
      await secondSuspension;
      wrote("t2");

      assert.strictEqual(Batches.close(), secondBatch);

      assert.deepStrictEqual(ids(firstBatch), ["t1"]);
      assert.deepStrictEqual(ids(secondBatch), ["t2"]);
    });

    // Awaiting a task twice takes nothing out of the promise registry, so this is what Task.await/1
    // hands over the second time. The action goes on to raise, and it can only drop its own writes
    // if it is still the one running.
    it("leaves the action running when there is nothing to await", () => {
      const batch = Batches.open("todos");

      assert.throw(() => Batches.carryAcrossSuspension(null), TypeError);

      assert.strictEqual(Batches.current(), batch);
    });

    // An action that raises after resuming has to drop its own writes, which it can only do if the
    // failure arrives with the batch back in place.
    it("puts the batch back when the awaited promise fails", async () => {
      const batch = Batches.open("first");
      const suspension = Batches.carryAcrossSuspension(
        Promise.reject(new Error("boom")),
      );

      Batches.open("second");

      let errorThrown = false;

      try {
        await suspension;
      } catch (error) {
        errorThrown = true;
        assert.equal(error.message, "boom");
      }

      assert.isTrue(errorThrown, "Expected the awaited promise to reject");
      assert.strictEqual(Batches.discard(), batch);
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

    it("leaves no batch running, so a write after it has nowhere to go", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      assert.isNull(Batches.current());
    });

    it("writes the batch down, and hands the write to the sender", () => {
      const recording = Promise.resolve();
      const writing = sinon.stub(Durability, "fileBatch").returns(recording);

      Batches.open("todos");
      wrote("t1");

      const batch = Batches.close();

      assert.isTrue(writing.calledOnceWithExactly(batch));
      assert.strictEqual(batch.recorded, recording);
    });

    describe("whether the store holds it", () => {
      const closedFiled = async (stored) => {
        Durability.mode = "indexeddb";
        sinon.stub(Durability, "fileBatch").resolves(stored);

        Batches.open("todos");
        wrote("t1");

        const batch = Batches.close();
        await batch.recorded;

        return batch;
      };

      it("is so once the store filed it", async () => {
        assert.isTrue((await closedFiled(true)).filed);
      });

      it("is not when the store failed to file it", async () => {
        assert.isFalse((await closedFiled(false)).filed);
      });

      it("is not with nowhere to file it", () => {
        Batches.open("todos");
        wrote("t1");

        assert.isFalse(Batches.close().filed);
      });
    });

    // The page that eventually sends this batch may belong to somebody else, and only a page
    // mounted under this user takes it up again.
    it("seals the batch under the page's user", () => {
      LocalDatabase.actorUserId = "u1";

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().actorUserId, "u1");
    });

    // Set BEFORE the write rather than after it. The record is built at the moment the batch is
    // written down, so an owner assigned afterwards would be stored as nobody - and no later page
    // load would ever take the batch up, whoever signed in.
    it("writes the batch down under the page's user", () => {
      LocalDatabase.actorUserId = "u1";

      let stored = null;

      sinon
        .stub(Durability, "fileBatch")
        .callsFake((batch) => (stored = batch.record()));

      Batches.open("todos");
      wrote("t1");
      Batches.close();

      assert.equal(stored.actorUserId, "u1");
    });

    // An action can be suspended across a login.
    describe("of an action whose user changed while it was open", () => {
      const closedAfterChange = () => {
        LocalDatabase.actorUserId = "u1";

        Batches.open("todos");
        wrote("t1");

        LocalDatabase.actorUserId = "u2";

        return Batches.close();
      };

      it("keeps the batch under the user who opened it", () => {
        assert.equal(closedAfterChange().actorUserId, "u1");
      });

      it("stores it under that user", () => {
        let stored = null;

        sinon.stub(Durability, "fileBatch").callsFake((batch) => {
          stored = batch.record();

          return Promise.resolve();
        });

        closedAfterChange();

        assert.equal(stored.actorUserId, "u1");
      });

      it("doesn't queue it", () => {
        closedAfterChange();

        assert.deepStrictEqual(Batches.pending, []);
      });

      it("takes its writes off the new user's screen", () => {
        closedAfterChange();

        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      // A tab that hasn't heard of the change would take it up and send it under the new session.
      it("doesn't tell the group about it", () => {
        const posting = sinon.stub(Tabs, "post");

        closedAfterChange();

        assert.isFalse(posting.called);
      });

      it("doesn't tell the group when the user changes before the store answers", async () => {
        const posting = sinon.stub(Tabs, "post");

        let answer;

        sinon
          .stub(Durability, "fileBatch")
          .returns(new Promise((resolve) => (answer = resolve)));

        Durability.mode = "indexeddb";
        LocalDatabase.actorUserId = "u1";

        Batches.open("todos");
        wrote("t1");
        const batch = Batches.close();

        LocalDatabase.actorUserId = "u2";

        answer();
        await batch.recorded;

        assert.isFalse(posting.called);
      });

      it("still spends a number", () => {
        assert.equal(closedAfterChange().seq, 1);

        Batches.open("todos");
        wrote("t2");

        assert.equal(Batches.close().seq, 2);
      });

      it("seals what the new user opens afterwards under them", () => {
        closedAfterChange();

        Batches.open("todos");
        wrote("t2");

        assert.equal(Batches.close().actorUserId, "u2");
        assert.equal(Batches.pending.length, 1);
      });
    });

    // UNDEFINED rather than null, which is what a page mount leaves when its data names no actor.
    // It has to reach the batch as null: the owner filter that decides whether a later load takes
    // the batch up compares with ===, and undefined would match nothing a page ever mounts under.
    // What puts a write made in one tab on the screen of the next before the server has heard of
    // it - and what lets the tab that sends send it without reading the store again.
    describe("telling the group", () => {
      const closedFiled = async (stored) => {
        Durability.mode = "indexeddb";
        sinon.stub(Durability, "fileBatch").callsFake(async (batch) => {
          batch.seal(7);

          return stored;
        });

        Batches.open("todos");
        wrote("t1");

        const batch = Batches.close();
        await batch.recorded;

        return batch;
      };

      it("tells it about a batch it has filed", async () => {
        const posting = sinon.stub(Tabs, "post");
        const batch = await closedFiled(true);

        assert.isTrue(
          posting.calledOnceWithExactly({
            kind: "sealed",
            record: batch.record(),
          }),
        );
      });

      // Its number was never written down, so the store can give it to another batch.
      it("says nothing of one the store failed to file", async () => {
        const posting = sinon.stub(Tabs, "post");

        await closedFiled(false);

        sinon.assert.notCalled(posting);
      });

      it("says nothing of one with nowhere to file it", () => {
        const posting = sinon.stub(Tabs, "post");

        Batches.open("todos");
        wrote("t1");
        Batches.close();

        sinon.assert.notCalled(posting);
      });
    });

    it("takes the number the store gives it", () => {
      sinon.stub(Durability, "fileBatch").callsFake((batch) => batch.seal(7));

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 7);
    });

    // What every tab did before there was anywhere to file a batch, and what a browser that cannot
    // store still does: nothing is shared, so nothing can collide.
    it("numbers the batch itself where there is nowhere to file it", () => {
      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 1);

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 2);
    });

    it("counts on from the highest number the store has given", () => {
      sinon.stub(Durability, "fileBatch").callsFake((batch) => batch.seal(7));

      Batches.open("todos");
      wrote("t1");
      Batches.close();

      sinon.restore();

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 8);
    });

    it("seals a visitor's batch under nobody", () => {
      LocalDatabase.actorUserId = undefined;

      Batches.open("todos");
      wrote("t1");

      assert.isNull(Batches.close().actorUserId);
    });

    // A batch waiting for the store to number it cannot be wrong at the tail: whatever number it
    // gets will be above every number already spent.
    it("keeps a batch waiting for its number at the tail, and files it in order", async () => {
      let file;

      const filing = new Promise((resolve) => {
        file = resolve;
      });

      // Adopting repaints, and this describe installs no animation frame to repaint into.
      sinon.stub(SyncStream, "scheduleRender");

      Durability.mode = "indexeddb";

      sinon
        .stub(Durability, "fileBatch")
        .callsFake((batch) => filing.then(() => batch.seal(4)));

      Batches.adopt([
        {actorUserId: null, landed: [], seq: 9, writes: [write("t9")]},
      ]);

      Batches.open("todos");
      wrote("t1");

      const batch = Batches.close();

      assert.deepStrictEqual(
        Batches.pending.map((held) => held.seq),
        [9, null],
      );

      file();
      await batch.recorded;

      assert.deepStrictEqual(
        Batches.pending.map((held) => held.seq),
        [4, 9],
      );
    });

    // The sort runs when a batch is numbered, and what it has to get right is the OTHER batch that
    // is still waiting for one: numbered or not, a batch behind this one in the queue was closed
    // after it and will be numbered above it.
    it("keeps a batch still waiting behind one that has just been numbered", async () => {
      const filings = [];

      // Adopting repaints, and this describe installs no animation frame to repaint into.
      sinon.stub(SyncStream, "scheduleRender");

      Durability.mode = "indexeddb";

      sinon.stub(Durability, "fileBatch").callsFake(
        (batch) =>
          new Promise((resolve) => {
            filings.push({batch, file: resolve});
          }),
      );

      Batches.open("todos");
      wrote("t1");

      const first = Batches.close();

      Batches.open("todos");
      wrote("t2");

      Batches.close();

      filings[0].batch.seal(4);
      filings[0].file();

      await first.recorded;

      assert.deepStrictEqual(
        Batches.pending.map((held) => held.seq),
        [4, null],
      );
    });

    it("answers nothing when no batch is open", () => {
      assert.isNull(Batches.close());
    });
  });

  describe("current()", () => {
    it("answers nothing when no action has opened one", () => {
      assert.isNull(Batches.current());
    });

    it("answers the batch of the action running now", () => {
      const batch = Batches.open("todos");

      assert.strictEqual(Batches.current(), batch);
    });
  });

  describe("recorded()", () => {
    it("settles once every sealed batch is written down", async () => {
      Batches.open("todos");
      wrote("t1");
      const batch = Batches.close();

      let record;

      batch.recorded = new Promise((resolve) => {
        record = resolve;
      });

      let settled = false;

      const waiting = Batches.recorded().then(() => {
        settled = true;
      });

      await waitForEventLoop();

      assert.isFalse(settled);

      record();
      await waiting;

      assert.isTrue(settled);
    });

    // The page is live through the wait, so an action can seal another batch meanwhile.
    it("waits for a batch sealed while it waits", async () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      let record;

      const waiting = Batches.recorded();

      Batches.open("todos");
      wrote("t2");

      Batches.close().recorded = new Promise((resolve) => {
        record = resolve;
      });

      let settled = false;

      waiting.then(() => {
        settled = true;
      });

      await waitForEventLoop();

      assert.isFalse(settled);

      record();
      await waiting;

      assert.isTrue(settled);
    });

    // A write that failed has said so already, and a page load waiting on it goes ahead.
    it("settles when a write failed", async () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close().recorded = Promise.reject(new Error("store gone"));

      await Batches.recorded();
    });

    it("settles at once with nothing sealed", async () => {
      await Batches.recorded();
    });

    describe("for a batch of another user", () => {
      let record, settled;

      const waitFor = async () => {
        settled = false;

        const waiting = Batches.recorded().then(() => {
          settled = true;
        });

        await waitForEventLoop();

        assert.isFalse(settled);

        record();
        await waiting;

        assert.isTrue(settled);
      };

      beforeEach(() => {
        sinon.stub(Durability, "fileBatch").returns(
          new Promise((resolve) => {
            record = resolve;
          }),
        );

        LocalDatabase.actorUserId = "u1";
        Batches.open("todos");
        wrote("t1");
      });

      it("waits for one closed after the user changed", async () => {
        LocalDatabase.actorUserId = "u2";
        Batches.close();

        await waitFor();
      });

      it("waits for one let go of while still being filed", async () => {
        Batches.close();

        LocalDatabase.actorUserId = "u2";
        Batches.releaseForeign("u2");

        await waitFor();
      });

      it("doesn't wait for it again once it is written down", async () => {
        LocalDatabase.actorUserId = "u2";

        const batch = Batches.close();

        record();
        await batch.recorded;
        await waitForEventLoop();

        batch.recorded = new Promise(() => {});

        await Batches.recorded();
      });
    });
  });

  describe("releaseForeign()", () => {
    const made = (owner, id) => {
      LocalDatabase.actorUserId = owner;

      Batches.open("todos");
      wrote(id);

      return Batches.close();
    };

    it("takes another user's batches out of the queue", () => {
      made("u1", "t1");
      const own = made("u2", "t2");

      Batches.releaseForeign("u2");

      assert.deepStrictEqual(Batches.pending, [own]);
    });

    it("takes them off the screen and keeps the user's own", () => {
      made("u1", "t1");
      made("u2", "t2");

      Batches.releaseForeign("u2");

      assert.isFalse(Overlay.names(TODO, "t1"));
      assert.isTrue(Overlay.names(TODO, "t2"));
    });

    // Their owner's next page takes them up from there.
    it("leaves them in the store", () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");

      made("u1", "t1");

      Batches.releaseForeign("u2");

      assert.isFalse(forgetting.called);
    });

    // An action suspended across the login has its writes on the screen before it is sealed.
    it("takes an open batch of another user off the screen", () => {
      LocalDatabase.actorUserId = "u1";

      Batches.open("todos");
      wrote("t1");

      Batches.releaseForeign("u2");

      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    // A mount can leave the actor undefined, and a visitor's batches are stamped null.
    it("keeps a visitor's own batches when named as undefined", () => {
      const own = made(null, "t1");

      Batches.releaseForeign(undefined);

      assert.deepStrictEqual(Batches.pending, [own]);
      assert.isTrue(Overlay.names(TODO, "t1"));
    });

    describe("of an action open when its user leaves and returns", () => {
      beforeEach(() => {
        LocalDatabase.actorUserId = "u1";

        Batches.open("todos");
        wrote("t1");

        Batches.releaseForeign("u2");
      });

      it("puts its writes back on the screen", () => {
        Batches.releaseForeign("u1");

        assert.isTrue(Overlay.names(TODO, "t1"));
      });

      it("puts them back once", () => {
        Batches.releaseForeign("u1");
        Batches.releaseForeign("u1");

        const held = Overlay.removeWhere((batch) => batch.state === "open");

        assert.equal(held.length, 1);
      });

      it("doesn't bring them back for another user", () => {
        Batches.releaseForeign("u3");

        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      // As a sealed batch, where no store holds it (see the tests below).
      it("brings back once one that closed while away", () => {
        LocalDatabase.actorUserId = "u2";
        const batch = Batches.close();

        Batches.releaseForeign("u1");

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.equal(Overlay.removeWhere(() => true).length, 1);
      });

      it("doesn't bring back one discarded while away", () => {
        Batches.discard();

        Batches.releaseForeign("u1");

        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      it("queues it when it closes after the return", () => {
        Batches.releaseForeign("u1");

        const batch = Batches.close();

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.isTrue(Overlay.names(TODO, "t1"));
      });
    });

    it("treats a visitor as a user of their own", () => {
      made(null, "t1");
      const own = made("u1", "t2");

      Batches.releaseForeign("u1");

      assert.deepStrictEqual(Batches.pending, [own]);
    });

    // Nothing else holds them, and nothing else will send them.
    describe("of a batch no store holds, when its user returns", () => {
      let batch;

      beforeEach(() => {
        batch = made("u1", "t1");

        Batches.releaseForeign("u2");
      });

      it("is held for that user while away", () => {
        assert.isTrue(Batches.heldFor("u1"));
        assert.isFalse(Batches.heldFor("u2"));
      });

      it("puts it back in the queue and on the screen", () => {
        Batches.releaseForeign("u1");

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.isTrue(Overlay.names(TODO, "t1"));
        assert.isFalse(Batches.heldFor("u1"));
      });

      it("puts it back once", () => {
        Batches.releaseForeign("u1");
        Batches.releaseForeign("u1");

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.equal(Overlay.removeWhere(() => true).length, 1);
      });

      it("doesn't put it back for another user", () => {
        Batches.releaseForeign("u3");

        assert.deepStrictEqual(Batches.pending, []);
        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      // Its send was out when the user changed, and its answer came after.
      it("doesn't put back one answered while away", () => {
        Batches.settle(batch.seq, {dropped: {}, kept: {}, status: "confirmed"});

        Batches.releaseForeign("u1");

        assert.deepStrictEqual(Batches.pending, []);
      });

      it("puts it ahead of the batches made since", () => {
        const later = made("u1", "t2");

        Batches.releaseForeign("u1");

        assert.deepStrictEqual(Batches.pending, [batch, later]);
      });
    });

    // Its owner's next page takes it up from there.
    it("holds nothing for a batch the store holds", () => {
      made("u1", "t1").filed = true;

      Batches.releaseForeign("u2");
      Batches.releaseForeign("u1");

      assert.isFalse(Batches.heldFor("u1"));
      assert.deepStrictEqual(Batches.pending, []);
    });

    it("holds a batch whose filing settles with no store", async () => {
      let file;

      sinon
        .stub(Durability, "fileBatch")
        .returns(new Promise((resolve) => (file = resolve)));

      Durability.mode = "indexeddb";
      const batch = made("u1", "t1");

      LocalDatabase.actorUserId = "u2";
      Batches.releaseForeign("u2");

      Durability.mode = "memory";
      file(false);
      await batch.recorded;
      await Promise.resolve();

      assert.isTrue(Batches.heldFor("u1"));
    });

    it("puts back a batch whose filing settles with no store after its user returned", async () => {
      let file;

      sinon
        .stub(Durability, "fileBatch")
        .returns(new Promise((resolve) => (file = resolve)));

      sinon.stub(Batches, "flush");

      Durability.mode = "indexeddb";
      const batch = made("u1", "t1");

      LocalDatabase.actorUserId = "u2";
      Batches.releaseForeign("u2");

      LocalDatabase.actorUserId = "u1";
      Batches.releaseForeign("u1");

      Durability.mode = "memory";
      file(false);
      await batch.recorded;
      await Promise.resolve();

      assert.deepStrictEqual(Batches.pending, [batch]);
      assert.isTrue(Overlay.names(TODO, "t1"));
    });

    // An action its user starts once back can undo what the batch did, and has to stay on top of
    // it.
    it("puts a batch whose filing was out while its user was away beneath an action started since", async () => {
      let file;

      globalThis.Hologram.sync = {model: TODO_MODEL};

      sinon
        .stub(Durability, "fileBatch")
        .returns(new Promise((resolve) => (file = resolve)));

      sinon.stub(Batches, "flush");

      const edge = (op) => ({
        id: "t1",
        op,
        relationship: "tags",
        target_id: "g1",
        type: TODO,
      });

      // A store that failed after the page had one, which numbers a batch only in its turn.
      Durability.hadStore = true;
      Durability.mode = "indexeddb";
      LocalDatabase.actorUserId = "u1";

      Batches.open("todos");
      Batches.current().append(edge("add_relationship"));
      const batch = Batches.close();

      LocalDatabase.actorUserId = "u2";
      Batches.releaseForeign("u2");

      LocalDatabase.actorUserId = "u1";
      Batches.releaseForeign("u1");

      Batches.open("todos");
      Batches.current().append(edge("delete_relationship"));

      Durability.mode = "memory";
      file(false);
      await batch.recorded;
      await Promise.resolve();

      try {
        assert.deepStrictEqual(
          Overlay.foldTargetIds(TODO, "tags", "t1", []),
          new Set(),
        );
      } finally {
        Batches.discard();
        Durability.hadStore = false;
        delete globalThis.Hologram.sync;
      }
    });

    // The store failed while the first was still being filed, so the second was set aside with no
    // number, and is the newer one all the same.
    it("puts a batch whose filing was out ahead of a later one set aside", async () => {
      let file;

      globalThis.Hologram.sync = {model: TODO_MODEL};

      sinon
        .stub(Durability, "fileBatch")
        .returns(new Promise((resolve) => (file = resolve)));

      sinon.stub(Batches, "flush");

      const edge = (op) => ({
        id: "t1",
        op,
        relationship: "tags",
        target_id: "g1",
        type: TODO,
      });

      Durability.hadStore = true;
      Durability.mode = "indexeddb";
      LocalDatabase.actorUserId = "u1";

      Batches.open("todos");
      Batches.current().append(edge("add_relationship"));
      const first = Batches.close();

      Durability.mode = "memory";

      Batches.open("todos");
      Batches.current().append(edge("delete_relationship"));
      const second = Batches.close();

      LocalDatabase.actorUserId = "u2";
      Batches.releaseForeign("u2");

      LocalDatabase.actorUserId = "u1";
      Batches.releaseForeign("u1");

      try {
        assert.deepStrictEqual(Batches.pending, [first, second]);

        assert.deepStrictEqual(
          Overlay.foldTargetIds(TODO, "tags", "t1", []),
          new Set(),
        );
      } finally {
        file(false);
        await first.recorded;
        Durability.hadStore = false;
        delete globalThis.Hologram.sync;
      }
    });
  });

  describe("disown()", () => {
    const STAMP = 1_798_246_400_125_952;

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.reset();
      Model.reset();

      sinon.stub(SyncStream, "scheduleRender");
    });

    afterEach(() => {
      LocalDatabase.reset();
    });

    it("lets every pending batch go, and takes its rows with it", () => {
      Batches.adopt([
        {
          actorUserId: null,
          landed: [],
          seq: 3,
          writes: [
            {
              data: {done: false, title: "made elsewhere"},
              id: "t1",
              op: "create",
              stamp: STAMP,
              type: TODO,
            },
          ],
        },
      ]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "made elsewhere");

      Batches.disown();

      assert.deepStrictEqual(Batches.pending, []);
      assert.isNull(LocalDatabase.getRow(TODO, "t1"));
    });

    // The numbers stay spent: what this tab has seen is still true, and a batch it makes next has
    // to be above them whatever identity it is making it under.
    it("leaves the numbers it has seen alone", () => {
      Batches.adopt([
        {actorUserId: null, landed: [], seq: 9, writes: [write("t9")]},
      ]);

      Batches.disown();

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 10);
    });

    describe("a batch this tab made", () => {
      let filings, sendStub;

      // Closes a batch whose filing settles when told to, stored under number 5 or not at all.
      const closeFiled = () => {
        Batches.open("todos");
        Batches.current().append({
          data: {done: false, title: "mine"},
          id: "t1",
          op: "create",
          stamp: STAMP,
          type: TODO,
        });

        const batch = Batches.close();

        return {batch, file: filings.at(-1)};
      };

      beforeEach(() => {
        filings = [];

        Durability.mode = "indexeddb";

        sinon.stub(Durability, "fileBatch").callsFake((batch) => {
          if (Durability.mode === "memory") return Promise.resolve(false);

          return new Promise((resolve) => {
            filings.push((stored) => {
              if (stored) {
                batch.seal(5);
              }

              resolve(stored);
            });
          });
        });

        sendStub = sinon.stub(Mutations, "send");
      });

      afterEach(() => {
        Durability.hadStore = false;
      });

      it("is let go of when the store holds it", async () => {
        const {batch, file} = closeFiled();

        file(true);
        await batch.recorded;

        Batches.disown();

        assert.deepStrictEqual(Batches.pending, []);
        assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      });

      // No other tab holds it, so letting it go would lose the write.
      it("is kept when the store never took it", async () => {
        const {batch, file} = closeFiled();

        file(false);
        await batch.recorded;

        Batches.disown();

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.equal(LocalDatabase.getRow(TODO, "t1").title, "mine");
      });

      it("is kept when there was no store to file it in", async () => {
        Durability.mode = "memory";

        const {batch} = closeFiled();

        await batch.recorded;

        assert.isFalse(batch.filed);

        Batches.disown();

        assert.deepStrictEqual(Batches.pending, [batch]);
      });

      // An action can run the next one in the same turn, so the second batch may update a row the
      // first created. They go out in the order they were made.
      it("numbers batches in order after a store that failed on the spot", async () => {
        const sent = [];

        Durability.hadStore = true;

        Durability.fileBatch.callsFake(async () => {
          Durability.mode = "memory";

          return false;
        });

        sendStub.callsFake(async (batch) => {
          sent.push(`${Replica.id}:${batch.seq}`);

          return {dropped: {}, kept: {}, status: "confirmed"};
        });

        const first = closeFiled().batch;

        // Known in the turn it closed, so it keeps its place ahead of the next batch.
        assert.isFalse(first.filed);

        const second = closeFiled().batch;

        await Promise.all([first.recorded, second.recorded]);

        assert.isNull(first.seq);
        assert.isNull(second.seq);

        Replica.requestMint();
        Replica.takeMinted({id: "r-minted", token: "statement-minted"});

        await Batches.flush();

        assert.deepStrictEqual(sent, ["r-minted:1", "r-minted:2"]);
        assert.equal(first.seq, 1);
        assert.equal(second.seq, 2);
      });

      it("is let go of once a filing in flight turns out to have stored it", async () => {
        const {batch, file} = closeFiled();

        Batches.disown();

        assert.deepStrictEqual(Batches.pending, [batch]);

        file(true);
        await batch.recorded;

        assert.deepStrictEqual(Batches.pending, []);
        assert.isNull(LocalDatabase.getRow(TODO, "t1"));
      });

      it("counts on from a filing let go of in flight", async () => {
        const {batch, file} = closeFiled();

        Batches.disown();

        file(true);
        await batch.recorded;

        Durability.mode = "memory";

        assert.equal(closeFiled().batch.seq, 6);
      });

      it("is kept once a filing in flight turns out to have failed", async () => {
        const {batch, file} = closeFiled();

        Batches.disown();

        file(false);
        await batch.recorded;

        assert.deepStrictEqual(Batches.pending, [batch]);
        assert.equal(LocalDatabase.getRow(TODO, "t1").title, "mine");
      });

      it("is not sent when it was let go of while the sender waited on its filing", async () => {
        const {batch, file} = closeFiled();

        const flushing = Batches.flush();

        await waitForEventLoop();

        Batches.disown();

        file(true);
        await batch.recorded;
        await flushing;

        sinon.assert.notCalled(sendStub);
      });
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

    it("leaves no batch running, so a write after it has nowhere to go", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.discard();

      assert.isNull(Batches.current());
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

  describe("adopt()", () => {
    const STAMP = 1_798_246_400_125_952;

    const stored = (seq, id, landed = []) => ({
      actorUserId: "u1",
      landed,
      seq,
      writes: [
        {
          data: {done: false, title: "stored"},
          id,
          op: "create",
          stamp: STAMP,
          type: TODO,
        },
      ],
    });

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.actorUserId = "u1";

      LocalDatabase.reset();
      Model.reset();

      // Taking a batch up puts a row on the screen, so it asks for a repaint - and this describe
      // installs no animation frame to repaint into.
      sinon.stub(SyncStream, "scheduleRender");
    });

    afterEach(() => {
      LocalDatabase.reset();

      // One test lifts the clock above this machine's wall clock, and a clock left there answers
      // every stamp in every suite that runs after this file.
      Clock.reset();
    });

    it("queues the stored batches oldest first", () => {
      Batches.adopt([stored(3, "t1"), stored(5, "t2")]);

      assert.deepStrictEqual(
        Batches.pending.map((batch) => batch.seq),
        [3, 5],
      );

      assert.deepStrictEqual(
        Batches.pending.map((batch) => batch.state),
        ["pending", "pending"],
      );
    });

    // On the screen before anything is sent, and out of the overlay rather than the base: what the
    // previous page load put there comes back with the batches that made it, still this client's
    // own unanswered work.
    it("folds their writes over the base", () => {
      Batches.adopt([stored(3, "t1")]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "stored");
      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    it("keeps their landed marks", () => {
      Batches.adopt([stored(3, "t1", [0])]);

      assert.isTrue(Batches.pending[0].isLanded(0));
    });

    // Waking the sender belongs to the page load, once everything it takes up is in place.
    //
    // The wait is load-bearing: the sender awaits the batch's own write before anything leaves, so
    // a synchronous assertion here passes whether or not this function sends - it would be reading
    // the moment before the first await either way.
    it("sends nothing", async () => {
      const sendStub = sinon.stub(Mutations, "send");

      Batches.adopt([stored(3, "t1")]);

      await waitForEventLoop();

      assert.isFalse(sendStub.called);
    });

    it("takes up nothing from an empty store", () => {
      Batches.adopt([]);

      assert.deepStrictEqual(Batches.pending, []);
    });

    it("puts a batch another tab filed in its place in the queue", () => {
      Batches.adopt([stored(5, "t2")]);
      Batches.adopt([stored(3, "t1")]);

      assert.deepStrictEqual(
        Batches.pending.map((batch) => batch.seq),
        [3, 5],
      );
    });

    // The batch holding the create can be the one that arrives late, and an update folded before
    // the create it updates finds no row.
    it("folds batches taken up out of order in number order", () => {
      const updating = {
        ...stored(4, "t1"),
        writes: [
          {
            data: {title: "edited"},
            id: "t1",
            op: "update",
            stamp: STAMP + 1,
            type: TODO,
          },
        ],
      };

      Batches.adopt([updating]);
      Batches.adopt([stored(3, "t1")]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "edited");
    });

    // A batch takes its place when it opens and its number later, so the numbers in the overlay
    // aren't in order: here the batch holding 10 sits ahead of 8.
    it("folds a late batch after the one it builds on, past a higher number ahead of it", () => {
      Durability.mode = "indexeddb";

      sinon.stub(Durability, "fileBatch").returns(new Promise(() => {}));

      Batches.open("todos");
      Batches.current().append(stored(0, "t9").writes[0]);

      const higher = Batches.close();

      Batches.open("todos");
      Batches.current().append(stored(0, "t1").writes[0]);

      const lower = Batches.close();

      lower.seal(8);
      higher.seal(10);

      Batches.adopt([
        {
          ...stored(9, "t1"),
          writes: [
            {
              data: {title: "edited"},
              id: "t1",
              op: "update",
              stamp: STAMP + 1,
              type: TODO,
            },
          ],
        },
      ]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "edited");
    });

    // It has never left this tab and ships after the late batch, so it can build on that batch.
    it("folds a batch still open after a late batch whose row it updates", () => {
      Batches.open("todos");
      Batches.current().append(stored(0, "t9").writes[0]);

      Batches.adopt([stored(3, "t2")]);

      Batches.current().append({
        data: {title: "edited"},
        id: "t2",
        op: "update",
        stamp: STAMP + 1,
        type: TODO,
      });

      assert.equal(LocalDatabase.getRow(TODO, "t2").title, "edited");
    });

    // A suspended action's batch has no number yet, and a later action wrote on top of what it
    // showed, so a batch arriving now moves neither of them.
    it("leaves a batch still open under the batch written on top of it", () => {
      Batches.resumeFrom(5);

      Batches.open("todos");
      Batches.current().append(stored(0, "t1").writes[0]);
      Batches.carryAcrossSuspension(new Promise(() => {}));

      Batches.open("todos");
      Batches.current().append({
        data: {title: "edited"},
        id: "t1",
        op: "update",
        stamp: STAMP + 1,
        type: TODO,
      });
      Batches.close();

      Batches.adopt([stored(3, "t2")]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "edited");
    });

    // Twice over the same record is what a tab gets when a message and the store both carry it -
    // and a batch held twice would be folded twice and sent twice.
    it("passes over a batch it already holds", () => {
      Batches.adopt([stored(3, "t1")]);
      Batches.adopt([stored(3, "t1")]);

      assert.equal(Batches.pending.length, 1);
    });

    // Left where it is rather than dropped: the server applies a batch under the user of the
    // session that sends it, so the page mounted under its owner is what takes it up.
    it("passes over another user's batch", () => {
      Batches.adopt([{...stored(3, "t1"), actorUserId: "u2"}]);

      assert.deepStrictEqual(Batches.pending, []);
    });

    describe("a batch already answered", () => {
      const answer = {dropped: {}, kept: {}, status: "confirmed"};

      it("passes over a batch it held when the answer came", () => {
        Batches.adopt([stored(3, "t1")]);
        Batches.settle(3, answer);

        Batches.adopt([stored(3, "t1")]);

        assert.deepStrictEqual(Batches.pending, []);
      });

      // The message announcing a batch and the answer to it can come from different tabs, so they
      // can reach this one in either order.
      it("passes over a batch whose answer arrived first", () => {
        Batches.settle(3, answer);

        Batches.adopt([stored(3, "t1")]);

        assert.deepStrictEqual(Batches.pending, []);
      });

      it("counts past its number", () => {
        Batches.settle(9, answer);

        Batches.adopt([stored(9, "t1")]);

        Batches.open("todos");
        wrote("t2");

        assert.equal(Batches.close().seq, 10);
      });

      // Answered before this tab read the store, so it never heard the answer.
      it("passes over a batch the store says was answered", () => {
        sinon.stub(Durability, "wasAnswered").withArgs(3).returns(true);

        Batches.adopt([stored(3, "t1"), stored(4, "t2")]);

        assert.deepStrictEqual(
          Batches.pending.map((batch) => batch.seq),
          [4],
        );
      });
    });

    // Even the ones it does not take. A number another tab has spent is a number this tab must not
    // spend, whoever made that batch - the server answers a repeat from the first one's record.
    it("counts past every number it is shown", () => {
      Batches.adopt([{...stored(9, "t1"), actorUserId: "u2"}]);

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 10);
    });

    // A batch this tab seals next may name a row one of these wrote, and its based_on for that
    // column is this stamp - a stamp of its own that did not clear it would be refused.
    //
    // AHEAD of this machine's wall clock, which is what makes the lifting observable at all: a
    // stamp is at least the wall clock, so a write stamped in the past is cleared whether or not
    // anything observed it. Ahead is also the case that matters - a burst of stamps inside one
    // millisecond runs ahead of the wall clock, and every tab of a browser shares one clock.
    it("lifts the clock past the writes it takes", () => {
      const ahead = Date.now() * 1024 + 10_000_000;
      const record = stored(3, "t1");

      record.writes[0].stamp = ahead;

      Batches.adopt([record]);

      assert.isAbove(Clock.stamp(), ahead);
    });

    it("repaints for what it took, and not for what it passed over", () => {
      const rendering = SyncStream.scheduleRender;

      Batches.adopt([{...stored(3, "t1"), actorUserId: "u2"}]);

      assert.isFalse(rendering.called);

      Batches.adopt([stored(4, "t2")]);

      assert.isTrue(rendering.calledOnce);
    });

    // A batch taken up seals before the open action does, so the server applies it first - and
    // the action reads its own write on top of it.
    it("folds a batch it takes under an action still open", () => {
      Batches.open("todos");

      Batches.current().append({
        data: {title: "open"},
        id: "t1",
        op: "update",
        stamp: STAMP + 1,
        type: TODO,
      });

      Batches.adopt([stored(3, "t1")]);

      assert.equal(LocalDatabase.getRow(TODO, "t1").title, "open");
    });
  });

  describe("resumeFrom()", () => {
    it("numbers the next sealed batch from above the given one", () => {
      Batches.resumeFrom(41);

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 42);
    });

    // A tab that moves to another group resumes from that group's store, whose count can be
    // behind a number this tab has already spent.
    it("never numbers below a batch it already numbered", () => {
      Batches.resumeFrom(50);
      Batches.resumeFrom(41);

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 51);
    });
  });
});

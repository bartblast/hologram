"use strict";

import {
  assert,
  defineRuntimeGlobals,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Client from "../../assets/js/client.mjs";
import Clock from "../../assets/js/clock.mjs";
import Durability from "../../assets/js/durability.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Replica from "../../assets/js/replica.mjs";
import Sse from "../../assets/js/sse.mjs";
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

    Replica.reset();
    sinon.restore();
  });

  const wrote = (id) => {
    Batches.current().append(write(id));
  };

  describe("flush()", () => {
    const STAMP = 1_798_246_400_125_952;

    let renderStub, sendStub;

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.reset();
      Model.reset();

      renderStub = sinon.stub(Sse, "scheduleRender");
      sendStub = sinon.stub(Client, "sendMutation");
    });

    afterEach(() => {
      sinon.restore();
      LocalDatabase.reset();
    });

    const confirmed = (dropped = {}, kept = {}) => ({
      dropped,
      kept,
      status: "confirmed",
    });

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

    // A batch made in any tab is filed in the one queue they share, so a follower that sent as well
    // would put a second copy of every batch on the wire under the same replica and number.
    it("sends nothing from a tab that does not lead the group", async () => {
      Tabs.leader = false;

      sealed(creating("t1", "first"));

      await Batches.flush();

      assert.isFalse(sendStub.called);
      assert.equal(Batches.pending.length, 1);
    });

    // The store is the order, not the messages: a batch filed by a tab that closed straight after
    // is in the queue with nothing said about it, and it ships before anything numbered above it.
    it("takes up what the store holds above what it has seen, before sending", async () => {
      const filed = {
        actorUserId: null,
        landed: [],
        seq: 3,
        writes: [creating("t3", "filed elsewhere")],
      };

      // Once, the way the store answers it: the read is exclusive of what this tab has already
      // seen, so a record it has taken up is not offered again.
      const reading = sinon.stub(Durability, "batchesAbove").resolves([]);

      reading.onFirstCall().resolves([filed]);

      sendStub.resolves(confirmed());

      await Batches.flush();

      assert.isTrue(sendStub.calledOnce);
      assert.equal(sendStub.firstCall.args[0].seq, 3);
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
        claim: null,
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
        claim: null,
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
        reason: 'Type.atom("nope")',
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

    // The answer arrives as the server spelled it, so the term a refusal carries is built here -
    // the one place anything needs it rather than the JSON it travelled as.
    it("reads the term a refusal's reason was encoded as", async () => {
      sealed(creating("t1", "first"));

      sendStub.resolves({
        reason:
          'Type.map([[Type.atom("slug"), Type.list([Type.atom("unique")])]])',
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

      assert.isTrue(forgetting.calledOnceWithExactly(1));
    });

    // Refused for the writes or refused for the build, it is answered either way - and a batch
    // kept for a resend would come back on a later page load as a write the user watched fail.
    it("forgets a refused batch", async () => {
      const forgetting = sinon.stub(Durability, "forgetBatch");

      sealed(creating("t1", "first"));

      sendStub.resolves({
        reason: 'Type.atom("nope")',
        status: "rejected",
        write: 0,
      });

      await Batches.flush();

      assert.isTrue(forgetting.calledOnceWithExactly(1));
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
          reason: 'Type.atom("nope")',
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
            claim: null,
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

      sinon.stub(Sse, "scheduleRender");
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
        reason: 'Type.atom("nope")',
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

      assert.isTrue(Sse.scheduleRender.called);
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

    // Taken at seal rather than at send: the page that eventually sends this batch may belong to
    // somebody else, and only a page mounted under this user takes it up again.
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

    // UNDEFINED rather than null, which is what a page mount leaves when its data names no actor.
    // It has to reach the batch as null: the owner filter that decides whether a later load takes
    // the batch up compares with ===, and undefined would match nothing a page ever mounts under.
    // What puts a write made in one tab on the screen of the next before the server has heard of
    // it - and what lets the tab that sends send it without reading the store again.
    it("tells the group about a batch it has filed", () => {
      const posting = sinon.stub(Tabs, "post");

      Batches.open("todos");
      wrote("t1");

      const batch = Batches.close();

      assert.isTrue(
        posting.calledOnceWithExactly({
          kind: "sealed",
          record: batch.record(),
        }),
      );
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
      sinon.stub(Sse, "scheduleRender");

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
      sinon.stub(Sse, "scheduleRender");

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

  describe("disown()", () => {
    const STAMP = 1_798_246_400_125_952;

    beforeEach(() => {
      globalThis.Hologram.sync = {model: TODO_MODEL};

      LocalDatabase.reset();
      Model.reset();

      sinon.stub(Sse, "scheduleRender");
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
              claim: null,
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
          claim: null,
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
      sinon.stub(Sse, "scheduleRender");
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
      const sendStub = sinon.stub(Client, "sendMutation");

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
      const rendering = Sse.scheduleRender;

      Batches.adopt([{...stored(3, "t1"), actorUserId: "u2"}]);

      assert.isFalse(rendering.called);

      Batches.adopt([stored(4, "t2")]);

      assert.isTrue(rendering.calledOnce);
    });
  });

  describe("resumeFrom()", () => {
    it("numbers the next sealed batch from above the given one", () => {
      Batches.resumeFrom(41);

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 42);
    });
  });
});

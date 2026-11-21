"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Durability from "../../assets/js/durability.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Model from "../../assets/js/model.mjs";
import Replica from "../../assets/js/replica.mjs";
import Sse from "../../assets/js/sse.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

// Without this the file passes only when something else in the run has installed sessionStorage
// first: a browser that cannot coordinate its tabs is told so through Logger, which writes there.
registerWebApis();

// The data layer's constants live on the runtime's global, `globalThis.Hologram.sync`, which the
// tests here set and restore.
defineRuntimeGlobals();

// Node's own BroadcastChannel, made to work under jsdom - it does not otherwise, and the reason is
// worth knowing before anyone treats this as decoration.
//
// Node builds the message event out of whatever `Event` is GLOBAL when its messaging internals
// first load, which under `jsdom-global` is jsdom's Event rather than its own - and its dispatch
// then refuses the very event it just built ("The 'event' argument must be an instance of Event.
// Received an instance of MessageEvent"). Taking the lock works, delivering a message does not.
//
// So Node's own Event is put back for exactly as long as it takes ONE MESSAGE to be delivered,
// which is the moment those internals build that class and keep it; afterwards jsdom's Event goes
// back and every later channel - in this file and in any other - delivers. A channel merely opened
// is not enough: the class is built when a message first arrives, so the warm-up has to complete a
// round trip. Node's Event is reached through an abort event, since nothing exports the class and
// jsdom has replaced the global.
//
// The alternative was a stand-in of our own, and this suite is about using the browser's real
// election and the browser's real channel correctly, so there is nothing a stand-in could say here.
const nodeEvent = await new Promise((resolve) => {
  const controller = new AbortController();

  controller.signal.addEventListener("abort", (event) =>
    resolve(event.constructor),
  );
  controller.abort();
});

const jsdomEvent = globalThis.Event;

globalThis.Event = nodeEvent;

await new Promise((resolve) => {
  const speaking = new BroadcastChannel("hologram.warmup");
  const listening = new BroadcastChannel("hologram.warmup");

  listening.onmessage = () => {
    speaking.close();
    listening.close();

    resolve();
  };

  speaking.postMessage(0);
});

globalThis.Event = jsdomEvent;

// The other tabs of the group are real: a Web Lock taken the way another tab would take it, and a
// BroadcastChannel of the same name. Nothing here stands in for the browser, because what this
// module claims is that it uses the browser's own election correctly.
describe("Tabs", () => {
  let groupCount = 0;
  let openChannels;
  let releases;

  // A group of its own per test. Locks and channels are named per process here exactly as they are
  // named per origin in a browser, so a lock one test leaves held would otherwise decide what the
  // next one sees.
  const nextGroup = () => `hologram.1.model-${++groupCount}.anonymous`;

  // Takes the group's lock the way another tab would, and answers what lets it go. Waits for the
  // grant, so a test that follows knows the lock is really taken rather than merely asked for.
  const holdLeaderLock = async (group) => {
    let granted;
    let release;

    const held = new Promise((resolve) => {
      release = resolve;
    });

    const isGranted = new Promise((resolve) => {
      granted = resolve;
    });

    navigator.locks.request(`${group}.leader`, () => {
      granted();

      return held;
    });

    await isGranted;
    releases.push(release);

    return release;
  };

  const isLockFree = (group) =>
    navigator.locks.request(
      `${group}.leader`,
      {ifAvailable: true},
      (lock) => lock !== null,
    );

  const sibling = (group) => {
    const channel = new BroadcastChannel(group);

    openChannels.push(channel);

    return channel;
  };

  const stubs = () => ({onLead: () => {}, onMessage: () => {}});

  // A group is only ever formed by a bundle with a data model, whose rules a tab hands on. What an
  // earlier file left there goes back afterwards.
  let originalSync;

  beforeEach(() => {
    openChannels = [];
    releases = [];

    originalSync = globalThis.Hologram.sync;

    globalThis.Hologram.sync = {
      model: {},
      policyHash: "0123456789abcdef",
      protocolVersion: 1,
    };
  });

  afterEach(async () => {
    await Tabs.leave();

    globalThis.Hologram.sync = originalSync;

    releases.forEach((release) => release());
    openChannels.forEach((channel) => channel.close());

    sinon.restore();
  });

  // What a tab does when the store it was sharing is gone: the group is over, and every tab goes
  // back to being a replica of its own.
  describe("dissolve()", () => {
    let disowning, reconnecting, wasStarted;

    beforeEach(() => {
      disowning = sinon.stub(Batches, "disown");
      reconnecting = sinon.stub(Sse, "reconnect");

      wasStarted = Sse.isStarted;
      Sse.isStarted = true;

      Replica.offer({id: "r-fresh", token: "statement-fresh"});
    });

    afterEach(() => {
      Sse.isStarted = wasStarted;
      Replica.reset();
    });

    it("leaves the group", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      await Tabs.dissolve();

      assert.isNull(Tabs.name);
      assert.isTrue(await isLockFree(group));
    });

    // Those batches were numbered under the identity this tab is holding, and it is the only tab
    // that can still send them.
    it("keeps the identity and the queue in the tab that was leading", async () => {
      await Tabs.join(nextGroup(), stubs());

      Replica.adopt({id: "r-group", token: "statement-group"});

      Tabs.dissolve();

      assert.equal(Replica.id, "r-group");
      assert.isFalse(disowning.called);
      assert.isFalse(reconnecting.called);
    });

    it("takes a fresh identity and lets the batches go in a tab that was following", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Replica.adopt({id: "r-group", token: "statement-group"});

      Tabs.dissolve();

      assert.equal(Replica.id, "r-fresh");
      assert.isTrue(disowning.calledOnce);
    });

    // The frames it was being handed stop here, so it needs a stream the server serves sync on.
    it("opens a stream of its own in a tab that was following", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Tabs.dissolve();

      assert.isTrue(reconnecting.calledOnce);
    });

    // The stream its page opens after the mount is its own already, and one opened before it would
    // carry none of the page's subscriptions.
    it("opens no stream in a tab that was following and has not started one", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Sse.isStarted = false;

      Tabs.dissolve();

      assert.isFalse(reconnecting.called);
      assert.isTrue(disowning.calledOnce);
    });

    // Asking for the lock speaks for nobody yet, so what the group handed it goes back.
    it("lets the batches go in a tab that was still asking for the lock", async () => {
      sinon.stub(navigator.locks, "request").resolves();

      Tabs.join(nextGroup(), stubs());

      Tabs.dissolve();

      assert.isTrue(disowning.calledOnce);
    });
  });

  // What a tab does the moment the group becomes its to lead, with nothing handed over by the tab
  // that was leading - which may have closed without warning.
  describe("taking the lead", () => {
    let clearing, flushing, reconnecting, repairing, wasStarted;

    // Takes the group's lock, hands this tab the follower's place in the queue behind it, and
    // answers what makes the tab lead. Waits for the lead to be taken, so what follows is settled.
    // The tab is ready first, as one that has been open a while is.
    const succeed = async (group) => {
      const release = await holdLeaderLock(group);

      await Tabs.join(group, {});

      Tabs.ready();

      release();

      await waitForEventLoop();
    };

    // The same, for a tab still starting up when the lead is handed to it: granted, and not ready.
    const handOverWhileStarting = async (group, handlers = {}) => {
      const release = await holdLeaderLock(group);

      await Tabs.join(group, handlers);

      release();

      await waitForEventLoop();
    };

    beforeEach(() => {
      // Reading the rows back for the repair asks the model which relationships are to-many, so a
      // suite with no model cannot build the argument at all.
      globalThis.Hologram.sync = {
        model: {
          "MyApp.Task": {
            attributes: {id: "uuid", title: "string"},
            enumValues: {},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();

      clearing = sinon.stub(Durability, "clear");
      flushing = sinon.stub(Batches, "flush");
      reconnecting = sinon.stub(Sse, "reconnect");
      repairing = sinon.stub(Durability, "repair").resolves();

      sinon.stub(Tabs, "postState");

      wasStarted = Sse.isStarted;
      Sse.isStarted = true;
    });

    afterEach(() => {
      Sse.isStarted = wasStarted;

      delete globalThis.Hologram.sync;

      LocalDatabase.reset();
      Model.reset();
      Replica.reset();

      SyncStream.syncCursor = null;
    });

    it("opens a stream of its own and starts sending", async () => {
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isTrue(Tabs.leader);
      assert.isTrue(reconnecting.calledOnce);
      assert.isTrue(flushing.calledOnce);
      assert.isTrue(Tabs.postState.calledOnce);
    });

    // The tab that was leading can have written something down and closed before telling the group,
    // and carrying on would leave the store naming a place this tab does not hold the rows for.
    it("brings the store to what it holds, when it has a place", async () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "from the stream"});

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isTrue(repairing.calledOnce);

      assert.deepStrictEqual(repairing.firstCall.args[1], "place-1");

      assert.deepStrictEqual(
        repairing.firstCall.args[0].map((record) => record.id),
        ["t1"],
      );

      assert.isFalse(clearing.called);
    });

    // The store goes, because it is dated by a place this tab does not have - but what is on the
    // screens does not. Every tab of the group keeps showing what it showed until the fill this
    // asks for says which of those rows are still this browser's.
    it("keeps its rows for the fill to confirm, when it has no place", async () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "from the stream"});

      sinon.stub(Tabs, "post");

      await succeed(nextGroup());

      assert.deepStrictEqual(LocalDatabase.baseRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "from the stream",
      });

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
      ]);
    });

    it("starts over when it has no place to resume from", async () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "from the stream"});

      const posting = sinon.stub(Tabs, "post");

      await succeed(nextGroup());

      assert.isTrue(clearing.calledOnce);
      assert.isFalse(repairing.called);

      assert.deepStrictEqual(posting.firstCall.args[0], {
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    });

    // Pins the check alone: a page always starts its stream in the same run as the restore, so a
    // tab holding a place has one by the time its lead is settled.
    it("opens no stream of its own when the page has not started one", async () => {
      SyncStream.syncCursor = "place-1";
      Sse.isStarted = false;

      await succeed(nextGroup());

      assert.isFalse(reconnecting.called);
      assert.isTrue(flushing.calledOnce);
      assert.isTrue(Tabs.postState.calledOnce);
    });

    // Until its restore a starting tab holds no place, and taking the lead without one is asking for
    // everything again over a store that has one.
    it("waits until it is ready to take the lead it was handed while starting", async () => {
      const led = sinon.spy();

      await handOverWhileStarting(nextGroup(), {onLead: led});

      assert.isTrue(Tabs.leader);
      assert.isFalse(led.called);

      Tabs.ready();

      assert.isTrue(led.calledOnce);
    });

    it("takes the lead from the place its restore handed it", async () => {
      await handOverWhileStarting(nextGroup());

      // What the restore does, from the place the store held.
      SyncStream.syncCursor = "place-1";

      Tabs.ready();
      await waitForEventLoop();

      assert.isTrue(repairing.calledOnce);
      assert.equal(repairing.firstCall.args[1], "place-1");
      assert.isFalse(clearing.called);
    });

    // The tab that was leading cleared the store to start over and closed before saying so, so the
    // place this tab holds is older than that start-over.
    it("starts over when the store it would repair holds no place", async () => {
      const posting = sinon.stub(Tabs, "post");

      let stated;

      Tabs.postState.callsFake(() => (stated = SyncStream.syncCursor));

      repairing.resolves(true);
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      // What the group is told names no place: the tabs that drop theirs on the resync would
      // otherwise take this one back.
      assert.isNull(stated);
      assert.isNull(SyncStream.syncCursor);
      assert.isTrue(clearing.calledOnce);
      assert.isTrue(reconnecting.calledOnce);

      sinon.assert.calledWith(posting, {
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    });

    // The page's stream greeted with no sync while this checked, so it is replaced.
    it("starts over on the stream the page started while it checked", async () => {
      let repaired;

      repairing.returns(new Promise((resolve) => (repaired = resolve)));
      Sse.isStarted = false;

      await handOverWhileStarting(nextGroup());

      SyncStream.syncCursor = "place-1";
      Tabs.ready();

      // What the page does right after the restore.
      Sse.isStarted = true;

      repaired(true);
      await waitForEventLoop();

      assert.isTrue(clearing.calledOnce);
      assert.isTrue(reconnecting.calledOnce);
    });

    // A stream the page opens while the lead is being settled is not served sync - a frame stored
    // then would land on a store about to be cleared - so it is replaced once that is settled.
    it("replaces the stream the page started while it decided", async () => {
      let repaired;

      repairing.returns(new Promise((resolve) => (repaired = resolve)));
      Sse.isStarted = false;

      await handOverWhileStarting(nextGroup());

      SyncStream.syncCursor = "place-1";
      Tabs.ready();

      assert.isTrue(Tabs.takingLead);

      // What the page does right after the restore.
      Sse.isStarted = true;

      repaired(false);
      await waitForEventLoop();

      assert.isFalse(Tabs.takingLead);
      assert.isTrue(reconnecting.calledOnce);
      assert.isTrue(flushing.calledOnce);
    });

    it("settles its lead even when the check fails", async () => {
      repairing.rejects(new Error("refused"));
      SyncStream.syncCursor = "place-1";

      // The lead's rejection goes nowhere: the lock's callback lets it drop.
      await succeed(nextGroup());

      assert.isFalse(Tabs.takingLead);
    });

    it("asks for everything when its restore left it no place", async () => {
      const posting = sinon.stub(Tabs, "post");

      Sse.isStarted = false;

      await handOverWhileStarting(nextGroup());

      assert.isFalse(clearing.called);

      Tabs.ready();
      await waitForEventLoop();

      assert.isTrue(clearing.calledOnce);
      assert.isFalse(repairing.called);
      assert.isFalse(reconnecting.called);

      sinon.assert.calledWith(posting, {
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    });

    it("takes no lead it was handed once it has left the group", async () => {
      const led = sinon.spy();

      await handOverWhileStarting(nextGroup(), {onLead: led});

      await Tabs.leave();

      Tabs.ready();

      assert.isFalse(led.called);
    });

    // The tab that led posted them, and they reached this tab after the lead did. Taken, a frame
    // would move the place this tab greets the server from past what the store holds.
    describe("what the tab before it still says", () => {
      const deltas = {
        event: "sync_deltas",
        frame: {applied_seq: 0, cursor: "place-2", deltas: []},
        kind: "frame",
      };

      const resync = {
        event: "sync_resync",
        frame: {reason: "identity"},
        kind: "frame",
      };

      const state = {
        completeness: {all: true, types: []},
        cursor: "place-2",
        kind: "state",
      };

      const answered = {answer: "ok", kind: "answered", seq: 3};
      const sealed = {kind: "sealed"};

      // Says the messages from another tab, with a sealed batch after them as the barrier.
      const say = (group, messages) => {
        const other = sibling(group);

        for (const message of [...messages, sealed]) {
          other.postMessage(message);
        }
      };

      // What this tab acts on, and a promise that the barrier say() posts last is in - so whatever
      // it took of the rest it has taken by then.
      const hearing = (receive = () => {}) => {
        const seen = [];

        let arrived;

        const hasHeard = new Promise((resolve) => {
          arrived = resolve;
        });

        const onMessage = (message) => {
          seen.push(message);

          if (message.kind === "sealed") {
            arrived();
          } else {
            receive(message);
          }
        };

        return {hasHeard, onMessage, seen};
      };

      const leadReady = async (group, handlers) => {
        const release = await holdLeaderLock(group);

        await Tabs.join(group, handlers);

        Tabs.ready();

        release();
        await waitForEventLoop();

        assert.isTrue(Tabs.leader);
      };

      it("passes over a frame and the group's state once it has taken the lead", async () => {
        SyncStream.syncCursor = "place-1";

        const group = nextGroup();
        const heard = hearing();

        await leadReady(group, heard);

        say(group, [deltas, state, answered]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [answered, sealed]);
      });

      it("passes them over as the first tab of the group", async () => {
        const group = nextGroup();
        const heard = hearing();

        assert.isTrue(await Tabs.join(group, heard));

        Tabs.ready();

        say(group, [deltas, state, answered]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [answered, sealed]);
      });

      it("takes them while it follows", async () => {
        const group = nextGroup();
        const heard = hearing();

        await holdLeaderLock(group);
        await Tabs.join(group, heard);

        Tabs.ready();

        say(group, [deltas, state, answered]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [deltas, state, answered, sealed]);
      });

      // The window the repair leaves open: the place it writes down is the one this tab greets from.
      it("keeps the place it repairs the store to while the repair is under way", async () => {
        SyncStream.syncCursor = "place-1";

        sinon.stub(SyncStream, "scheduleRender");

        let finishRepair;

        repairing.returns(new Promise((resolve) => (finishRepair = resolve)));

        const group = nextGroup();
        const heard = hearing(Tabs.receive);

        await leadReady(group, heard);

        assert.isTrue(Tabs.takingLead);

        say(group, [deltas]);
        await heard.hasHeard;

        finishRepair(false);
        await waitForEventLoop();

        assert.equal(SyncStream.syncCursor, "place-1");
      });

      // Somebody else signing in is said once, to the stream it happened on.
      // Taken for real, so the stream it opens is seen to greet from nowhere.
      it("takes a frame starting over, and starts over itself", async () => {
        SyncStream.syncCursor = "place-1";

        sinon.stub(Logger, "debug");

        const group = nextGroup();
        const heard = hearing(Tabs.receive);

        await leadReady(group, heard);

        clearing.resetHistory();
        reconnecting.resetHistory();

        let greetedFrom;

        reconnecting.callsFake(() => (greetedFrom = SyncStream.syncCursor));

        say(group, [resync]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [resync, sealed]);

        sinon.assert.calledOnce(clearing);
        sinon.assert.calledOnce(reconnecting);

        assert.isNull(greetedFrom);
      });

      // The server says any other start-over again, to this tab's own greeting.
      it("passes over a frame starting over for any other reason", async () => {
        const group = nextGroup();
        const heard = hearing();

        await leadReady(group, heard);

        clearing.resetHistory();
        reconnecting.resetHistory();

        say(group, [{...resync, frame: {reason: "gap"}}]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [sealed]);

        sinon.assert.notCalled(clearing);
        sinon.assert.notCalled(reconnecting);
      });

      // The lead being taken opens the stream once it has settled, from the place this leaves.
      it("leaves the stream to a lead still being taken when a frame starting over arrives", async () => {
        SyncStream.syncCursor = "place-1";

        let finishRepair;

        repairing.returns(new Promise((resolve) => (finishRepair = resolve)));

        sinon.stub(Logger, "debug");

        const group = nextGroup();
        const heard = hearing(Tabs.receive);

        await leadReady(group, heard);

        reconnecting.resetHistory();

        let greetedFrom;

        reconnecting.callsFake(() => (greetedFrom = SyncStream.syncCursor));

        say(group, [resync]);
        await heard.hasHeard;

        sinon.assert.calledOnce(clearing);
        sinon.assert.notCalled(reconnecting);

        finishRepair(false);
        await waitForEventLoop();

        sinon.assert.calledOnce(reconnecting);

        assert.isNull(greetedFrom);
      });
    });

    describe("what it held while starting", () => {
      const answered = {answer: "ok", kind: "answered", seq: 3};
      const frame = {
        event: "synced",
        frame: {cursor: "place-9", scope: "all"},
        kind: "frame",
      };
      const state = {
        completeness: {all: true, types: []},
        cursor: "place-9",
        kind: "state",
        replica: {id: "r-group", token: "statement-group"},
      };

      // Delivered behind a lock someone else holds, so the tab follows and holds them, and then the
      // lock goes to it. A barrier that is not held says they have all arrived.
      const holdThenHandOver = async (
        seen,
        {messages = [frame, state, answered], onLead = () => {}} = {},
      ) => {
        const group = nextGroup();
        const release = await holdLeaderLock(group);

        let arrived;

        const hasArrived = new Promise((resolve) => {
          arrived = resolve;
        });

        await Tabs.join(group, {
          onLead,
          onMessage: (message) => {
            seen.push(message);

            if (message.kind === "sealed") {
              arrived();
            }
          },
        });

        const other = sibling(group);

        for (const message of messages) {
          other.postMessage(message);
        }

        other.postMessage({kind: "sealed"});

        await hasArrived;

        release();
        await waitForEventLoop();
      };

      // It asks for everything, and what it held is the tail of a fill that began before it was
      // listening: replayed, the marker would call the pot complete over the tail's rows alone.
      it("drops the fill and the group's state when it leads with no place, and keeps the answers", async () => {
        const seen = [];

        await holdThenHandOver(seen);

        Tabs.ready();

        assert.deepStrictEqual(seen, [{kind: "sealed"}, answered]);
      });

      // Said only once, and the one start-over that drops the rows at once: the refill would leave
      // the previous person's rows readable until it ends, this page's own among them.
      it("keeps a start-over for somebody else signing in when it leads with no place", async () => {
        const resync = {
          event: "sync_resync",
          frame: {reason: "identity"},
          kind: "frame",
        };

        const seen = [];

        await holdThenHandOver(seen, {
          messages: [frame, resync, state, answered],
        });

        Tabs.ready();

        assert.deepStrictEqual(seen, [{kind: "sealed"}, resync, answered]);
      });

      // Read before the leader wrote it, the store can lack the identity the queue was numbered
      // under - and this tab sends the queue now.
      it("takes and writes down the identity the group's state names when it leads with no place", async () => {
        const persisting = sinon.stub(Durability, "persistReplica");

        await holdThenHandOver([]);

        Tabs.ready();

        assert.equal(Replica.id, "r-group");

        sinon.assert.calledOnceWithExactly(persisting, {
          id: "r-group",
          token: "statement-group",
        });
      });

      // A start over held behind it is what the lead has to take, from the place the replay leaves.
      it("takes the lead after replaying what it held", async () => {
        const group = nextGroup();
        const release = await holdLeaderLock(group);

        await Tabs.join(group, {});

        let arrived;

        const hasArrived = new Promise((resolve) => {
          arrived = resolve;
        });

        sinon.stub(Batches, "adopt").callsFake(() => arrived());

        const other = sibling(group);

        other.postMessage({
          event: "sync_resync",
          frame: {reason: "rules"},
          kind: "frame",
        });

        other.postMessage({kind: "sealed", record: {}});

        await hasArrived;

        release();
        await waitForEventLoop();

        SyncStream.syncCursor = "place-1";

        Tabs.ready();
        await waitForEventLoop();

        assert.isTrue(clearing.calledOnce);
        assert.isFalse(repairing.called);
      });

      it("takes the identity the last state names", async () => {
        const earlier = {
          ...state,
          replica: {id: "r-old", token: "statement-old"},
        };

        await holdThenHandOver([], {messages: [earlier, state]});

        Tabs.ready();

        assert.equal(Replica.id, "r-group");
      });

      it("keeps the identity it has when the state names none", async () => {
        Replica.offer({id: "r-page", token: "statement-page"});

        const persisting = sinon.stub(Durability, "persistReplica");
        const anonymous = {...state, replica: {id: null, token: null}};

        await holdThenHandOver([], {messages: [anonymous]});

        Tabs.ready();

        assert.equal(Replica.id, "r-page");
        assert.isFalse(persisting.called);
      });

      // The lead says what this tab holds to the group, and that has to name the identity it now
      // sends under.
      it("takes the identity before taking the lead", async () => {
        let posted;

        Tabs.postState.callsFake(() => (posted = Replica.id));

        // Null takes the real lead, where an absent one takes none.
        await holdThenHandOver([], {onLead: null});

        Tabs.ready();
        await waitForEventLoop();

        assert.equal(posted, "r-group");
      });

      it("replays everything when it leads from a place", async () => {
        const seen = [];
        const persisting = sinon.stub(Durability, "persistReplica");

        await holdThenHandOver(seen);

        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.isFalse(persisting.called);

        assert.deepStrictEqual(seen, [
          {kind: "sealed"},
          frame,
          state,
          answered,
        ]);
      });
    });
  });

  describe("postState()", () => {
    afterEach(() => {
      LocalDatabase.reset();
      Replica.reset();

      SyncStream.stopReason = null;
      SyncStream.syncCursor = null;
    });

    // What a joining tab cannot read out of the store: what is complete, which nothing writes down,
    // the place and the identity as they stand now, and whether the server stopped serving this
    // tab.
    it("says what this tab knows that the store cannot tell", () => {
      const posting = sinon.stub(Tabs, "post");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);
      Replica.offer({id: "r-group", token: "statement-group"});

      SyncStream.stopReason = "model_hash";
      SyncStream.syncCursor = "place-1";

      Tabs.postState();

      assert.deepStrictEqual(posting.firstCall.args[0], {
        completeness: {all: false, types: ["MyApp.Task"]},
        cursor: "place-1",
        kind: "state",
        replica: {id: "r-group", token: "statement-group"},
        rules: null,
        stopReason: "model_hash",
        synced: [],
      });
    });

    // Builds of one model and one protocol share a group, and a tab of an earlier build iterates
    // the scopes it is told - so they travel as the list it reads, whose "all" both builds share.
    it("tells a tab of an earlier build the whole pot as the list of scopes it reads", () => {
      const posting = sinon.stub(Tabs, "post");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);
      LocalDatabase.markAllSynced();

      Tabs.postState();

      assert.deepStrictEqual(posting.firstCall.args[0].synced, ["all"]);
    });

    // A tab whose bundle was current when its stream connected is handed no rules, and a tab
    // joining it with an older bundle still needs the ones the group syncs under.
    it("hands over this bundle's own rules when the server handed this tab none", () => {
      const posting = sinon.stub(Tabs, "post");

      globalThis.Hologram.sync = {
        model: {"MyApp.Doc": {policy: {}}},
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };

      SyncStream.served = true;

      try {
        Tabs.postState();
      } finally {
        SyncStream.served = false;
      }

      assert.deepStrictEqual(posting.firstCall.args[0].rules, {
        policy_hash: "0123456789abcdef",
        protocol_version: 1,
        rules: {"MyApp.Doc": {constraints: {}, defaults: {}, policy: {}}},
      });
    });

    it("hands over the rules the server handed this tab in place of its bundle's", () => {
      const posting = sinon.stub(Tabs, "post");
      const rules = {
        policy_hash: "fedcba9876543210",
        protocol_version: 1,
        rules: {},
      };

      SyncStream.rules = rules;

      try {
        Tabs.postState();
      } finally {
        SyncStream.rules = null;
      }

      assert.deepStrictEqual(posting.firstCall.args[0].rules, rules);
    });
  });

  describe("receive()", () => {
    beforeEach(() => {
      sinon.stub(SyncStream, "receiveFrame");
      sinon.stub(LocalDatabase, "markAllSynced");
      sinon.stub(LocalDatabase, "markTypesSynced");
    });

    afterEach(() => {
      LocalDatabase.reset();
      Replica.reset();
      SyncStream.syncCursor = null;
    });

    it("applies a frame to this tab's own memory", () => {
      const frame = {applied_seq: null, cursor: "place-1", deltas: {}};

      Tabs.receive({event: "sync_deltas", frame, kind: "frame"});

      assert.isTrue(
        SyncStream.receiveFrame.calledOnceWithExactly("sync_deltas", frame),
      );
    });

    // A leader of an earlier build names the page its stream was greeted with, and the tab hands
    // the marker on whatever page it is on - receiveFrame is what passes over a scope it does not
    // know.
    it("hands on an earlier build's page marker whatever page it names", () => {
      Tabs.receive({
        event: "synced",
        frame: {cursor: "place-1", scope: "page"},
        kind: "frame",
        page: "MyApp.SettingsPage",
      });

      assert.isTrue(SyncStream.receiveFrame.calledOnce);
    });

    // A follower greets with nothing and is told nothing, so this is how it learns.
    it("takes a stop another tab was told about", () => {
      const frame = {protocol_version: 1, reason: "model_hash"};

      Tabs.receive({event: "sync_reload", frame, kind: "frame"});

      sinon.assert.calledOnceWithExactly(
        SyncStream.receiveFrame,
        "sync_reload",
        frame,
      );
    });

    it("takes up a batch another tab has filed", () => {
      const adopting = sinon.stub(Batches, "adopt");
      const record = {actorUserId: null, landed: [], seq: 3, writes: []};

      Tabs.receive({kind: "sealed", record});

      assert.isTrue(adopting.calledOnceWithExactly([record]));
    });

    // The tab that sends does not wait to read the store again for a batch it has just been told
    // about - and a tab that does not send has nothing to wake.
    it("wakes the sender for a filed batch when it leads", () => {
      sinon.stub(Batches, "adopt");

      const flushing = sinon.stub(Batches, "flush");

      Tabs.receive({
        kind: "sealed",
        record: {actorUserId: null, landed: [], seq: 3, writes: []},
      });

      assert.isTrue(flushing.calledOnce);
    });

    it("leaves the sender alone for a filed batch when it follows", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, {onLead: () => {}});

      sinon.stub(Batches, "adopt");

      const flushing = sinon.stub(Batches, "flush");

      Tabs.receive({
        kind: "sealed",
        record: {actorUserId: null, landed: [], seq: 3, writes: []},
      });

      assert.isFalse(flushing.called);
    });

    it("settles the answer a message carries", () => {
      const settling = sinon.stub(Batches, "settle");
      const answer = {dropped: {}, kept: {}, status: "confirmed"};

      Tabs.receive({answer, kind: "answered", seq: 3});

      assert.isTrue(settling.calledOnceWithExactly(3, answer));
    });

    // What that tab wiped it wiped for the whole browser, so this one stops writing too - and the
    // group ends, because the store was what made it one.
    it("lets the store go, and the group with it, when another tab could not write", () => {
      const detaching = sinon.stub(Durability, "detach");
      const dissolving = sinon.stub(Tabs, "dissolve");

      Tabs.receive({kind: "storage_failed"});

      assert.isTrue(detaching.calledOnce);
      assert.isTrue(dissolving.calledOnce);
    });

    it("answers a tab that has joined with the group's state, when it leads", async () => {
      await Tabs.join(nextGroup(), {onLead: () => {}});

      const posting = sinon.stub(Tabs, "post");

      Tabs.receive({kind: "joined"});

      assert.isTrue(posting.calledOnce);
      assert.equal(posting.firstCall.args[0].kind, "state");
    });

    // The place it holds may be about to go, and it says what it holds once that is settled.
    it("answers a tab that has joined with nothing, while it settles its lead", async () => {
      await Tabs.join(nextGroup(), {onLead: () => {}});

      const posting = sinon.stub(Tabs, "post");

      Tabs.takingLead = true;

      try {
        Tabs.receive({kind: "joined"});
      } finally {
        Tabs.takingLead = false;
      }

      assert.isFalse(posting.called);
    });

    it("answers a tab that has joined with nothing, when it follows", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, {onLead: () => {}});

      const posting = sinon.stub(Tabs, "post");

      Tabs.receive({kind: "joined"});

      assert.isFalse(posting.called);
    });

    it("takes the identity, the place and what is complete from the group's state", () => {
      Tabs.receive({
        cursor: "place-1",
        kind: "state",
        replica: {id: "r-group", token: "statement-group"},
        completeness: {all: true, types: ["MyApp.Task"]},
        synced: ["all"],
      });

      assert.equal(Replica.id, "r-group");
      assert.equal(SyncStream.syncCursor, "place-1");

      sinon.assert.calledOnceWithExactly(LocalDatabase.markTypesSynced, [
        "MyApp.Task",
      ]);

      sinon.assert.calledOnce(LocalDatabase.markAllSynced);
    });

    it("leaves everything unmarked while the group's state says only types are complete", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        completeness: {all: false, types: ["MyApp.Task"]},
        synced: [],
      });

      sinon.assert.notCalled(LocalDatabase.markAllSynced);
    });

    // Its own reading has already brought it further, or to somewhere else entirely.
    it("keeps a place it already holds", () => {
      SyncStream.syncCursor = "place-2";

      Tabs.receive({
        cursor: "place-1",
        kind: "state",
        replica: {id: null, token: null},
        completeness: {all: false, types: []},
        synced: [],
      });

      assert.equal(SyncStream.syncCursor, "place-2");
    });

    // The group's rows were judged under the rules its stream was handed, so a tab whose bundle
    // answers by others takes those.
    it("takes the rules the group syncs under when its bundle's are others", () => {
      const rules = {
        policy_hash: "fedcba9876543210",
        protocol_version: 1,
        rules: {},
      };

      globalThis.Hologram.sync = {policyHash: "0123456789abcdef"};

      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        rules,
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.calledOnceWithExactly(
        SyncStream.receiveFrame,
        "sync_rules",
        rules,
      );
    });

    it("keeps its bundle's rules when they are the ones the group syncs under", () => {
      globalThis.Hologram.sync = {policyHash: "fedcba9876543210"};

      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        rules: {
          policy_hash: "fedcba9876543210",
          protocol_version: 1,
          rules: {},
        },
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.notCalled(SyncStream.receiveFrame);
    });

    // For a tab joining a group whose stream was stopped before it arrived: the frame that said so
    // went out before it was listening.
    it("takes the stop the group's state names", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        stopReason: "protocol_version",
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.calledOnceWithExactly(
        SyncStream.receiveFrame,
        "sync_reload",
        {reason: "protocol_version"},
      );
    });

    it("takes no stop from a group's state naming none", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        stopReason: null,
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.notCalled(SyncStream.receiveFrame);
    });

    it("takes no stop from a group's state without the key", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.notCalled(SyncStream.receiveFrame);
    });

    it("takes the whole pot from the state of a tab of an earlier build", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        synced: ["all", "page"],
      });

      sinon.assert.calledOnceWithExactly(LocalDatabase.markTypesSynced, []);
      sinon.assert.calledOnce(LocalDatabase.markAllSynced);
    });

    // The page scope an earlier build spoke of names no type, and says nothing about the whole pot.
    it("takes nothing from the state of a tab of an earlier build holding only the page scope", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        synced: ["page"],
      });

      sinon.assert.calledOnceWithExactly(LocalDatabase.markTypesSynced, []);
      sinon.assert.notCalled(LocalDatabase.markAllSynced);
    });
  });

  describe("join()", () => {
    it("leads when nobody holds the group's lock", async () => {
      assert.isTrue(await Tabs.join(nextGroup(), stubs()));
      assert.isTrue(Tabs.leader);
    });

    // For the tab that joins while this one is still asking for the lock: it finds the lock taken,
    // follows, and asks for the state - and nothing answers, because the tab that would was not
    // leading yet when it asked.
    it("says what it holds to a group it has just taken the lead of", async () => {
      const posting = sinon.stub(Tabs, "post");

      await Tabs.join(nextGroup(), stubs());

      assert.equal(posting.firstCall.args[0].kind, "state");
    });

    it("says nothing to a group it has joined as a follower", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);

      const posting = sinon.stub(Tabs, "post");

      await Tabs.join(group, stubs());

      assert.isFalse(posting.called);
    });

    it("follows when another tab holds it", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);

      assert.isFalse(await Tabs.join(group, stubs()));
      assert.isFalse(Tabs.leader);
    });

    it("takes the lead when the holder lets go", async () => {
      const group = nextGroup();
      const release = await holdLeaderLock(group);

      let led;

      const hasLed = new Promise((resolve) => {
        led = resolve;
      });

      await Tabs.join(group, {onLead: led, onMessage: () => {}});

      Tabs.ready();

      release();
      await hasLed;

      assert.isTrue(Tabs.leader);
    });

    // A store failure another tab reports can end the group while this tab is still asking for the
    // lock, and what the tab is from then on is what leaving made it.
    it("leads itself when it left the group while asking to follow", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);

      const joining = Tabs.join(group, stubs());

      await Tabs.leave();

      assert.isTrue(await joining);
      assert.isTrue(Tabs.leader);
      assert.isNull(Tabs.name);
    });

    // Granted after the visit ended, a lock kept would be one nothing ever lets go of, and no tab
    // of the group could lead it again. The grant is driven by hand: here a free lock is granted
    // inside the request itself, before anything could leave.
    it("keeps no lock it was granted after it left the group", async () => {
      let grant;

      sinon
        .stub(navigator.locks, "request")
        .callsFake((_name, _options, callback) => {
          grant = callback;

          return new Promise(() => {});
        });

      Tabs.join(nextGroup(), stubs());

      await Tabs.leave();

      assert.isUndefined(grant({}));
    });

    // A batch another tab seals during the ask is not this tab's to send.
    it("leads nothing while it asks for the lock", async () => {
      sinon.stub(navigator.locks, "request").resolves();

      Tabs.join(nextGroup(), stubs());

      assert.isFalse(Tabs.leader);
    });

    // Where the browser cannot lock, its database is in memory mode for the same reason - so there
    // is no shared counter to protect, and a tab that speaks for nobody is what every tab there is.
    it("leads itself where the browser cannot coordinate its tabs", async () => {
      const navigator = Object.getOwnPropertyDescriptor(
        globalThis,
        "navigator",
      );

      try {
        Object.defineProperty(globalThis, "navigator", {
          configurable: true,
          value: {},
        });

        assert.isTrue(await Tabs.join(nextGroup(), stubs()));
        assert.isTrue(Tabs.leader);
        assert.isNull(Tabs.name);
      } finally {
        Object.defineProperty(globalThis, "navigator", navigator);
      }
    });

    it("names the group it joined", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      assert.equal(Tabs.name, group);
    });

    it("hands a sibling's message to the handler it was given", async () => {
      const group = nextGroup();

      let received;

      const hasReceived = new Promise((resolve) => {
        received = resolve;
      });

      await Tabs.join(group, {onLead: () => {}, onMessage: received});

      sibling(group).postMessage({kind: "sealed"});

      assert.deepStrictEqual(await hasReceived, {kind: "sealed"});
    });
  });

  describe("leave()", () => {
    it("releases the lock so another tab can take it", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());
      await Tabs.leave();

      assert.isTrue(await isLockFree(group));
    });

    // A tab whose group dissolved while it was settling its lead has no lead left to settle.
    it("settles no lead afterwards", async () => {
      await Tabs.join(nextGroup(), stubs());

      Tabs.takingLead = true;

      await Tabs.leave();

      assert.isFalse(Tabs.takingLead);
    });

    it("leads itself afterwards", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());
      await Tabs.leave();

      assert.isTrue(Tabs.leader);
      assert.isNull(Tabs.name);
    });

    // A tab that leaves while waiting is granted the lock eventually anyway, and what it does with
    // that grant has to be nothing - it belongs to a group this tab is no longer in.
    it("does not take the lead of the group it joined next", async () => {
      const left = nextGroup();
      const joined = nextGroup();
      const release = await holdLeaderLock(left);

      await Tabs.join(left, stubs());
      await Tabs.leave();

      const led = sinon.spy();

      await holdLeaderLock(joined);
      await Tabs.join(joined, {onLead: led, onMessage: () => {}});

      release();
      await waitForEventLoop();

      assert.isFalse(led.called);
      assert.isFalse(Tabs.leader);
    });
  });

  describe("ready()", () => {
    const frame = (id) => ({event: "sync_deltas", frame: id, kind: "frame"});

    // The barrier is not decoration: a message that is NOT held travels the same channel behind the
    // two that are, and a channel keeps one sender's order - so its arrival is what says the frames
    // have been delivered and held rather than merely not delivered yet.
    const barrier = {kind: "sealed"};

    it("holds frames until the tab is ready and drains them in order", async () => {
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "sealed") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage(frame(1));
      other.postMessage(frame(2));
      other.postMessage(barrier);

      await hasArrived;

      assert.deepStrictEqual(seen, [barrier]);

      Tabs.ready();

      assert.deepStrictEqual(seen, [barrier, frame(1), frame(2)]);
    });

    // A follower's: the tab that leads passes the frames it hears over.
    it("hands a frame straight through once the tab is ready", async () => {
      const group = nextGroup();
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await holdLeaderLock(group);

      await Tabs.join(group, {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);
          arrived();
        },
      });

      Tabs.ready();

      sibling(Tabs.name).postMessage(frame(1));

      await hasArrived;

      assert.deepStrictEqual(seen, [frame(1)]);
    });

    // Marking the pot complete is what sweeps the rows a page carried, and a sweep before the mount
    // sweeps an empty set - leaving the page's own carried rows to sit there for the life of the
    // tab. Reachable whenever a tab is between joining and mounting while another posts state.
    it("holds the group's state until the tab is ready", async () => {
      const state = {
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        completeness: {all: true, types: []},
        synced: ["all"],
      };

      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "sealed") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage(state);
      other.postMessage(barrier);

      await hasArrived;

      assert.deepStrictEqual(seen, [barrier]);

      Tabs.ready();

      assert.deepStrictEqual(seen, [barrier, state]);
    });

    // An answer names a batch this tab takes up in the same breath, and settling before the batch
    // is there settles nothing - leaving it folded for ever, since nothing answers it twice.
    it("holds an answer until the tab is ready", async () => {
      const answer = {
        answer: {dropped: {}, kept: {}, status: "confirmed"},
        kind: "answered",
        seq: 3,
      };

      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "sealed") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage(answer);
      other.postMessage(barrier);

      await hasArrived;

      assert.deepStrictEqual(seen, [barrier]);

      Tabs.ready();

      assert.deepStrictEqual(seen, [barrier, answer]);
    });

    it("holds nothing a starting tab can act on at once", async () => {
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);
          arrived();
        },
      });

      sibling(Tabs.name).postMessage(barrier);

      await hasArrived;

      assert.deepStrictEqual(seen, [barrier]);
    });
  });

  describe("post()", () => {
    it("reaches a tab listening on the group's channel", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      let received;

      const hasReceived = new Promise((resolve) => {
        received = resolve;
      });

      sibling(group).onmessage = (event) => received(event.data);

      Tabs.post({kind: "joined"});

      assert.deepStrictEqual(await hasReceived, {kind: "joined"});
    });

    it("carries a queued write's big integer to another tab as a BigInt", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      let received;

      const hasReceived = new Promise((resolve) => {
        received = resolve;
      });

      sibling(group).onmessage = (event) => received(event.data);

      Tabs.post({
        kind: "sealed",
        record: {
          writes: [
            {
              deltas: {
                n: Model.unbox(Type.integer(9007199254740993n), "integer"),
              },
            },
          ],
        },
      });

      const message = await hasReceived;

      assert.strictEqual(message.record.writes[0].deltas.n, 9007199254740993n);
    });

    it("says nothing outside a group", () => {
      assert.doesNotThrow(() => Tabs.post({kind: "joined"}));
    });

    describe("after a write", () => {
      let finishWrite, write;

      // What a sibling hears once it has heard `count` messages, posted by `post`.
      const hear = (group, count, post) => {
        const heard = [];

        const hasHeard = new Promise((resolve) => {
          sibling(group).onmessage = (event) => {
            heard.push(event.data);

            if (heard.length === count) {
              resolve(heard);
            }
          };
        });

        post();

        return hasHeard;
      };

      // What any channel posts, seen as it posts it - the channel of a visit that has ended too: a
      // channel delivers on a task of its own, so a sibling having heard nothing yet says nothing
      // about whether anything was posted.
      const watchPosts = () =>
        sinon.spy(BroadcastChannel.prototype, "postMessage");

      beforeEach(() => {
        write = new Promise((resolve) => (finishWrite = resolve));
      });

      // A frame told before its write landed can be lost from the store by this tab closing, while
      // the tabs that heard it go on holding it.
      it("waits for the write before posting", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        const posting = watchPosts();

        Tabs.post({kind: "frame"}, write);

        await waitForEventLoop();

        sinon.assert.notCalled(posting);

        const heard = await hear(group, 1, finishWrite);

        assert.deepStrictEqual(heard, [{kind: "frame"}]);
        sinon.assert.calledOnce(posting);
      });

      // A state naming a place, or a marker, must not reach a tab ahead of the rows it vouches for.
      it("keeps what follows behind a message still waiting for its write", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        const posting = watchPosts();

        Tabs.post({kind: "frame"}, write);
        Tabs.post({kind: "state"});

        await waitForEventLoop();

        sinon.assert.notCalled(posting);

        const heard = await hear(group, 2, finishWrite);

        assert.deepStrictEqual(heard, [{kind: "frame"}, {kind: "state"}]);
      });

      it("posts at once again once nothing is waiting", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        await hear(group, 1, () => {
          Tabs.post({kind: "frame"}, write);
          finishWrite();
        });

        const posting = watchPosts();

        Tabs.post({kind: "state"});

        sinon.assert.calledOnceWithExactly(posting, {kind: "state"});
      });

      // Its channel is closed by then, and posting on a closed channel throws.
      it("posts nothing on the channel of a visit that has ended", async () => {
        const debugging = sinon.spy(Logger, "debug");
        const rejections = [];
        const record = (reason) => rejections.push(reason);

        process.on("unhandledRejection", record);

        try {
          await Tabs.join(nextGroup(), stubs());

          Tabs.post({kind: "frame"}, write);

          await Tabs.leave();

          finishWrite();
          await waitForEventLoop();
          await waitForEventLoop();
        } finally {
          process.off("unhandledRejection", record);
        }

        assert.deepStrictEqual(rejections, []);
        assert.isFalse(debugging.called);
      });

      // A visit that ended leaves nothing waiting in the next one.
      it("posts at once in a group it joined again while a message waited", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        Tabs.post({kind: "frame"}, write);

        await Tabs.leave();
        await Tabs.join(group, stubs());

        const posting = watchPosts();

        Tabs.post({kind: "state"});

        sinon.assert.calledOnceWithExactly(posting, {kind: "state"});
      });

      // The ended visit's write finishing must not count against what waits in the next one.
      it("keeps waiting in the next visit when the ended one's write finishes", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        Tabs.post({kind: "frame"}, write);

        await Tabs.leave();
        await Tabs.join(group, stubs());

        const posting = watchPosts();

        Tabs.post({kind: "frame"}, new Promise(() => {}));

        finishWrite();
        await waitForEventLoop();

        Tabs.post({kind: "state"});
        await waitForEventLoop();

        sinon.assert.notCalled(posting);
      });

      // A write that fails still lets its message go, and the ones behind it.
      it("posts past a write that failed", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        const heard = await hear(group, 2, () => {
          Tabs.post({kind: "frame"}, Promise.reject(new Error("refused")));
          Tabs.post({kind: "state"});
        });

        assert.deepStrictEqual(heard, [{kind: "frame"}, {kind: "state"}]);
      });

      // Neither the post nor saying so may break the chain, or the next message would go out past
      // the write it waits for.
      it("keeps waiting for writes after a post that threw", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        const native = BroadcastChannel.prototype.postMessage;

        const posting = sinon
          .stub(BroadcastChannel.prototype, "postMessage")
          .onFirstCall()
          .throws(new DOMException("Could not be cloned.", "DataCloneError"))
          .callsFake(function (message) {
            return native.call(this, message);
          });

        sinon.stub(Logger, "debug").throws(new Error("storage full"));

        Tabs.post({kind: "frame"}, Promise.resolve());
        Tabs.post({kind: "frame", later: true}, write);

        await waitForEventLoop();

        sinon.assert.calledOnce(posting);
        sinon.assert.calledOnce(Logger.debug);

        const heard = await hear(group, 1, finishWrite);

        assert.deepStrictEqual(heard, [{kind: "frame", later: true}]);
      });

      // A write that fails while an earlier message is still waiting is handled as it fails, not
      // reported as a failure nothing saw.
      it("handles a write that fails while it waits its turn", async () => {
        const rejections = [];
        const record = (reason) => rejections.push(reason);

        process.on("unhandledRejection", record);

        try {
          await Tabs.join(nextGroup(), stubs());

          Tabs.post({kind: "frame"}, write);
          Tabs.post(
            {kind: "frame", later: true},
            Promise.reject(new Error("refused")),
          );

          await waitForEventLoop();
          await waitForEventLoop();
        } finally {
          process.off("unhandledRejection", record);
        }

        assert.deepStrictEqual(rejections, []);
      });

      // An ended visit's chain is not the next one's.
      it("posts a message whose write landed in a group it joined again", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        Tabs.post({kind: "frame"}, new Promise(() => {}));

        await Tabs.leave();
        await Tabs.join(group, stubs());

        const heard = await hear(group, 1, () => {
          Tabs.post({kind: "frame", later: true}, Promise.resolve());
        });

        assert.deepStrictEqual(heard, [{kind: "frame", later: true}]);
      });

      it("says nothing to a group it left while the message waited", async () => {
        const group = nextGroup();

        await Tabs.join(group, stubs());

        Tabs.post({kind: "frame"}, write);

        await Tabs.leave();

        // Joined again, so a channel is there to post on - it is another visit's.
        await Tabs.join(group, stubs());

        const posting = watchPosts();

        finishWrite();
        await waitForEventLoop();

        sinon.assert.notCalled(posting);
      });
    });
  });
});

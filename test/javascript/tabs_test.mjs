"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Clock from "../../assets/js/clock.mjs";
import Durability from "../../assets/js/durability.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
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

    // A tab that followed its page to another user holds that user's group's pair, which the
    // group's leader goes on sending under.
    it("holds no identity in a tab that was following with no fresh one to take", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Replica.fresh = null;
      Replica.adopt({id: "r-group", token: "statement-group"});

      try {
        Tabs.dissolve();

        assert.isNull(Replica.id);
        assert.isNull(Replica.token);
        assert.isTrue(SyncStream.awaitingPair);
      } finally {
        SyncStream.awaitingPair = false;
      }
    });

    // It followed the server to a pair every tab of the browser was handed, which the group's
    // leader goes on sending under.
    it("holds no identity in a tab that was following whose fresh one is the group's", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Replica.adopt({id: "r-group", token: "statement-group"});
      Replica.fresh = {id: "r-group", token: "statement-group"};

      try {
        Tabs.dissolve();

        assert.isNull(Replica.id);
        assert.isNull(Replica.token);
        assert.isTrue(SyncStream.awaitingPair);
      } finally {
        SyncStream.awaitingPair = false;
      }
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

    // It holds the lock, so it sends the queue - but its stream is still a follower's, which the
    // server serves no sync on.
    it("keeps the queue and opens a stream of its own in a tab handed a lead it has not taken", async () => {
      const group = nextGroup();
      const release = await holdLeaderLock(group);

      await Tabs.join(group, stubs());

      release();
      await waitForEventLoop();

      assert.isTrue(Tabs.leader);

      Replica.adopt({id: "r-group", token: "statement-group"});

      Tabs.dissolve();

      assert.equal(Replica.id, "r-group");
      assert.isFalse(disowning.called);
      assert.isTrue(reconnecting.calledOnce);
    });

    // What it held is dropped as it leaves, and a tab reading the store again - not ready either -
    // was doing so because its place was in doubt.
    it("greets the server from nowhere in a tab that is not ready", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      SyncStream.syncCursor = "place-1";

      try {
        Tabs.dissolve();

        assert.isNull(SyncStream.syncCursor);
      } finally {
        SyncStream.syncCursor = null;
      }
    });

    it("keeps the place of a tab that is ready", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      Tabs.ready();

      SyncStream.syncCursor = "place-1";

      try {
        Tabs.dissolve();

        assert.equal(SyncStream.syncCursor, "place-1");
      } finally {
        SyncStream.syncCursor = null;
      }
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

    // A tab that followed wrote no identity down, and a reload after a lost answer would send the
    // stored batch again under a new pair.
    it("writes down the identity it sends under before it sends", async () => {
      let persisted;

      const persisting = sinon
        .stub(Durability, "persistReplica")
        .returns(new Promise((resolve) => (persisted = resolve)));

      Replica.offer({id: "r-1", token: "statement-1"});
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      sinon.assert.calledOnceWithExactly(persisting, {
        id: "r-1",
        token: "statement-1",
      });

      assert.isFalse(flushing.called);

      persisted();
      await waitForEventLoop();

      assert.isTrue(flushing.calledOnce);
    });

    // What it says waits for that write (see postState).
    it("starts writing down the identity before it says what it holds", async () => {
      const persisting = sinon.stub(Durability, "persistReplica").resolves();

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      sinon.assert.callOrder(persisting, Tabs.postState);
      sinon.assert.calledOnce(persisting);
    });

    it("writes down the identity when it starts over", async () => {
      const persisting = sinon.stub(Durability, "persistReplica").resolves();

      sinon.stub(Tabs, "post");

      Replica.offer({id: "r-1", token: "statement-1"});

      await succeed(nextGroup());

      // After the clear, which leaves the identity where it is: the two land in the order made.
      sinon.assert.callOrder(clearing, persisting);

      sinon.assert.calledOnceWithExactly(persisting, {
        id: "r-1",
        token: "statement-1",
      });

      assert.isTrue(flushing.calledOnce);
    });

    // A batch another tab files, an action and the stream opening all flush too.
    it("sends nothing from anywhere until the identity is written down", async () => {
      let persisted;

      sinon
        .stub(Durability, "persistReplica")
        .returns(new Promise((resolve) => (persisted = resolve)));

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isFalse(Tabs.sends());

      persisted();
      await waitForEventLoop();

      assert.isTrue(Tabs.sends());
    });

    it("leaves the lead of a later visit to settle", async () => {
      const persisted = [];

      sinon
        .stub(Durability, "persistReplica")
        .callsFake(() => new Promise((resolve) => persisted.push(resolve)));

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());
      await Tabs.leave();
      await succeed(nextGroup());

      persisted[0]();
      await waitForEventLoop();

      assert.isFalse(Tabs.sends());
    });

    // A lead still writing its identity down when the tab left belongs to the visit that ended.
    it("sends once ready in a group it joins after leaving a lead it had not settled", async () => {
      sinon.stub(Durability, "persistReplica").returns(new Promise(() => {}));

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isFalse(Tabs.sends());

      await Tabs.leave();
      await Tabs.join(nextGroup(), {onLead: () => {}, onMessage: () => {}});

      Tabs.ready();

      assert.isTrue(Tabs.sends());
    });

    // Its restore flushes right after ready(), and a batch it held is replayed in it: both before
    // the lead has written anything down.
    it("sends nothing until the identity is written down, when handed the lead while starting", async () => {
      let persisted;

      sinon
        .stub(Durability, "persistReplica")
        .returns(new Promise((resolve) => (persisted = resolve)));

      await handOverWhileStarting(nextGroup());

      SyncStream.syncCursor = "place-1";

      Tabs.ready();

      assert.isFalse(Tabs.sends());

      await waitForEventLoop();

      assert.isFalse(Tabs.sends());

      persisted();
      await waitForEventLoop();

      assert.isTrue(Tabs.sends());
    });

    // It would be greeted with no sync until then: its page's place is not one it can vouch for
    // yet.
    it("is served no sync until it takes the lead it was handed while starting", async () => {
      await handOverWhileStarting(nextGroup(), {onLead: () => {}});

      assert.isTrue(Tabs.takingLead);

      Tabs.ready();

      assert.isFalse(Tabs.takingLead);
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

    // A tab that followed the session to another user reads that user's store again, and the lead
    // of their group can come to it meanwhile.
    it("waits until it is ready to take the lead it was handed while moving", async () => {
      const led = sinon.spy();
      const to = nextGroup();

      await Tabs.join(nextGroup(), {onLead: led, onMessage: () => {}});
      Tabs.ready();
      led.resetHistory();

      const release = await holdLeaderLock(to);
      const visit = await Tabs.move(to);

      assert.isFalse(Tabs.leader);

      release();
      await waitForEventLoop();

      assert.isTrue(Tabs.isVisit(visit));
      assert.isTrue(Tabs.leader);
      assert.isTrue(Tabs.takingLead);
      assert.isFalse(Tabs.sends());
      assert.isFalse(led.called);

      Tabs.ready();

      assert.isTrue(led.calledOnce);
      assert.isFalse(Tabs.takingLead);
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

    it("does not start over for a group it left while the store answered", async () => {
      const posting = sinon.stub(Tabs, "post");

      let repaired;

      repairing.returns(new Promise((resolve) => (repaired = resolve)));
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      Tabs.leave();

      repaired(true);
      await waitForEventLoop();

      assert.equal(SyncStream.syncCursor, "place-1");
      assert.isFalse(clearing.called);
      assert.isFalse(reconnecting.called);
      assert.isFalse(Tabs.postState.called);
      assert.isFalse(posting.called);
    });

    // The tab holds the next group's pair, or none, and the slot it would write is this group's.
    it("writes no identity down for a group it left while the store answered", async () => {
      const persisting = sinon.stub(Durability, "persistReplica").resolves();

      let repaired;

      repairing.returns(new Promise((resolve) => (repaired = resolve)));
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      Tabs.leave();

      repaired(false);
      await waitForEventLoop();

      assert.isFalse(persisting.called);
    });

    // The lead that would have replaced its follower's stream stops when it finds the group gone.
    it("opens a stream of its own when the group ends while the store answers", async () => {
      let repaired;

      repairing.returns(new Promise((resolve) => (repaired = resolve)));
      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isTrue(Tabs.takingLead);

      Tabs.dissolve();

      assert.isTrue(reconnecting.calledOnce);

      repaired(false);
      await waitForEventLoop();

      assert.isTrue(reconnecting.calledOnce);
    });

    it("leaves the next group's lead being taken when an older one answers", async () => {
      const answers = [];

      repairing.callsFake(
        () => new Promise((resolve) => answers.push(resolve)),
      );

      SyncStream.syncCursor = "place-1";

      await succeed(nextGroup());

      Tabs.leave();

      await succeed(nextGroup());

      assert.isTrue(Tabs.takingLead);

      answers[0](false);
      await waitForEventLoop();

      assert.isTrue(Tabs.takingLead);

      answers[1](false);
      await waitForEventLoop();

      assert.isFalse(Tabs.takingLead);
    });

    it("settles its lead even when the check fails", async () => {
      const persisting = sinon.stub(Durability, "persistReplica").resolves();

      repairing.rejects(new Error("refused"));
      SyncStream.syncCursor = "place-1";

      // The lead's rejection goes nowhere: the lock's callback lets it drop.
      await succeed(nextGroup());

      assert.isFalse(Tabs.takingLead);

      // Sending again, under an identity written down.
      assert.isTrue(persisting.calledOnce);
      assert.isTrue(Tabs.sends());
      assert.isTrue(flushing.calledOnce);
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
      const barrier = {kind: "barrier"};

      // Says the messages from another tab, with a message nothing acts on after them as the
      // barrier.
      const say = (group, messages) => {
        const other = sibling(group);

        for (const message of [...messages, barrier]) {
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

          if (message.kind === "barrier") {
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

        assert.deepStrictEqual(heard.seen, [answered, barrier]);
      });

      it("passes them over as the first tab of the group", async () => {
        const group = nextGroup();
        const heard = hearing();

        assert.isTrue(await Tabs.join(group, heard));

        Tabs.ready();

        say(group, [deltas, state, answered]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [answered, barrier]);
      });

      // Passed over for what it says of the rows. What model the server runs is no claim about
      // them, and a returning tab's own first frame names none.
      it("keeps the model the server runs from a state it passes over", async () => {
        const group = nextGroup();
        const heard = hearing();

        assert.isTrue(await Tabs.join(group, heard));

        say(group, [{...state, servedModelHash: "b7e1d4"}]);
        await heard.hasHeard;

        try {
          Tabs.ready();

          assert.deepStrictEqual(heard.seen, [barrier]);
          assert.equal(SyncStream.servedModelHash, "b7e1d4");
        } finally {
          SyncStream.servedModelHash = null;
        }
      });

      it("takes them while it follows", async () => {
        const group = nextGroup();
        const heard = hearing();

        await holdLeaderLock(group);
        await Tabs.join(group, heard);

        Tabs.ready();

        say(group, [deltas, state, answered]);
        await heard.hasHeard;

        assert.deepStrictEqual(heard.seen, [deltas, state, answered, barrier]);
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

        assert.deepStrictEqual(heard.seen, [resync, barrier]);

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

        assert.deepStrictEqual(heard.seen, [barrier]);

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

            if (message.kind === "barrier") {
              arrived();
            }
          },
        });

        const other = sibling(group);

        for (const message of messages) {
          other.postMessage(message);
        }

        other.postMessage({kind: "barrier"});

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

        assert.deepStrictEqual(seen, [{kind: "barrier"}, answered]);
      });

      // A filed batch is about the queue, which the fill it asks for does not replace.
      it("keeps a batch another tab filed when it leads with no place", async () => {
        const sealed = {kind: "sealed", record: {seq: 4}};
        const seen = [];

        await holdThenHandOver(seen, {
          messages: [frame, sealed, state, answered],
        });

        Tabs.ready();

        assert.deepStrictEqual(seen, [{kind: "barrier"}, sealed, answered]);
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

        assert.deepStrictEqual(seen, [{kind: "barrier"}, resync, answered]);
      });

      // Read before the leader wrote it, the store can lack the identity the queue was numbered
      // under - and this tab sends the queue now.
      it("takes and writes down the identity the group's state names when it leads with no place", async () => {
        const persisting = sinon.stub(Durability, "persistReplica").resolves();

        sinon.stub(Tabs, "post");

        // Null takes the real lead, where an absent one takes none.
        await holdThenHandOver([], {onLead: null});

        Tabs.ready();
        await waitForEventLoop();

        assert.equal(Replica.id, "r-group");

        sinon.assert.calledOnceWithExactly(persisting, {
          id: "r-group",
          token: "statement-group",
        });
      });

      // The restore wrote its page's pair over the one the tab that led had written since, and the
      // state is what still names it. The handler here takes nothing, so the lead itself does.
      it("takes the identity the group's state names when it leads from a place", async () => {
        await holdThenHandOver([], {messages: [state]});

        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.equal(Replica.id, "r-group");
      });

      // A start over held behind it is what the lead has to take, from the place the replay leaves.
      it("takes the lead after replaying what it held", async () => {
        const group = nextGroup();
        const release = await holdLeaderLock(group);

        let arrived;

        const hasArrived = new Promise((resolve) => {
          arrived = resolve;
        });

        await Tabs.join(group, {
          onMessage: (message) =>
            message.kind === "barrier" ? arrived() : Tabs.receive(message),
        });

        const other = sibling(group);

        other.postMessage({
          event: "sync_resync",
          frame: {reason: "rules"},
          kind: "frame",
        });

        other.postMessage({kind: "barrier"});

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

        const anonymous = {...state, replica: {id: null, token: null}};

        await holdThenHandOver([], {messages: [anonymous]});

        Tabs.ready();

        assert.equal(Replica.id, "r-page");
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

      // Replayed ahead of the lead, it would be answered with the place from before the repair.
      it("drops a request for the state when it leads from a place", async () => {
        const seen = [];

        await holdThenHandOver(seen, {messages: [{kind: "joined"}, answered]});

        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.deepStrictEqual(seen, [{kind: "barrier"}, answered]);
      });

      it("replays everything when it leads from a place", async () => {
        const seen = [];

        await holdThenHandOver(seen);

        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.deepStrictEqual(seen, [
          {kind: "barrier"},
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

      SyncStream.servedModelHash = null;
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

      SyncStream.servedModelHash = "b7e1d4";
      SyncStream.stopReason = "model_hash";
      SyncStream.syncCursor = "place-1";

      Tabs.postState();

      assert.deepStrictEqual(posting.firstCall.args[0], {
        completeness: {all: false, types: ["MyApp.Task"]},
        cursor: "place-1",
        kind: "state",
        replica: {id: "r-group", token: "statement-group"},
        rules: null,
        servedModelHash: "b7e1d4",
        stopReason: "model_hash",
        synced: [],
      });
    });

    // A first tab takes the store's identity over the one a held state names, so a state must
    // never name one the store could still lose.
    it("says what it holds only once the identity it names is written down", () => {
      const written = new Promise(() => {});
      const posting = sinon.stub(Tabs, "post");

      sinon.stub(Durability, "replicaWritten").returns(written);

      Tabs.postState();

      assert.equal(posting.firstCall.args[0].kind, "state");
      assert.strictEqual(posting.firstCall.args[1], written);
    });

    // Before its restore the tab holds its page's identity and no place, not the ones the store
    // gave it.
    it("says nothing while the tab is still starting up in a group", async () => {
      await Tabs.join(nextGroup(), stubs());

      const posting = sinon.stub(Tabs, "post");

      Tabs.postState();

      assert.isFalse(posting.called);
    });

    // The group's state names what is complete with no number, so it says nothing about whether
    // the fill read the batch behind a row this tab filed from an answer.
    it("keeps a row an answer filed when the group's state names its type", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "created here"});
      LocalDatabase.markPromoted("MyApp.Task", "t1", 3);

      Tabs.receive({
        completeness: {all: false, types: ["MyApp.Task"]},
        cursor: null,
        kind: "state",
        synced: [],
      });

      assert.isNotNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
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

      Tabs.ready();

      const posting = sinon.stub(Tabs, "post");

      Tabs.receive({kind: "joined"});

      assert.isTrue(posting.calledOnce);
      assert.equal(posting.firstCall.args[0].kind, "state");
    });

    // The place it holds may be about to go, and it says what it holds once that is settled.
    it("answers a tab that has joined with nothing, while it settles its lead", async () => {
      await Tabs.join(nextGroup(), {onLead: () => {}});

      Tabs.ready();

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

    // Its own reading has already brought it further, or to somewhere else entirely - a tab that
    // leads itself, as one in no group does. (A tab that follows reads the store again, below.)
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

    it("takes the model the group's server runs", () => {
      const noting = sinon.stub(SyncStream, "noteServedModel");

      Tabs.receive({
        cursor: null,
        kind: "state",
        replica: {id: null, token: null},
        servedModelHash: "b7e1d4",
        stopReason: null,
        completeness: {all: false, types: []},
        synced: [],
      });

      sinon.assert.calledOnceWithExactly(noting, "b7e1d4");
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

    // A tab that follows and holds another place than its group names was not brought there by its
    // own reading: the leader can have repaired the store somewhere it never followed.
    describe("the group's state, in a tab that follows", () => {
      const record = (id, title) => ({
        facts: {},
        id,
        row: {id, title},
        type: "MyApp.Task",
      });

      const state = (cursor, extra = {}) => ({
        completeness: {all: true, types: []},
        cursor,
        kind: "state",
        replica: {id: null, token: null},
        synced: ["all"],
        ...extra,
      });

      // Behind somebody else's lock, and ready, as a tab that has been open a while is.
      const follow = async (handlers = {}) => {
        const group = nextGroup();
        const release = await holdLeaderLock(group);

        await Tabs.join(group, {onLead: () => {}, ...handlers});

        Tabs.ready();

        return {group, release};
      };

      let actor, rendering;

      beforeEach(() => {
        // Nobody is signed in, as the stored rows here say: a tab takes up only a store its own
        // user's group filled, and the user is not reset between files.
        actor = LocalDatabase.actorUserId;
        LocalDatabase.actorUserId = null;

        rendering = sinon.stub(SyncStream, "scheduleRender");

        // Completeness is not reset between files either, and a claim already made sweeps nothing.
        LocalDatabase.reset();

        LocalDatabase.putRow("MyApp.Task", {id: "t-vouched", title: "held"});
        LocalDatabase.putRow("MyApp.Task", {id: "t-carried", title: "page"});
        LocalDatabase.markCarried("MyApp.Task", "t-carried");

        SyncStream.syncCursor = "place-1";
      });

      afterEach(() => {
        LocalDatabase.actorUserId = actor;
      });

      it("takes up the store when the group's state names another place", async () => {
        const reading = sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [
            record("t-stored", "stored"),
            record("t-carried", "stored"),
          ],
        });

        await follow();

        Tabs.receive(state("place-3"));
        await waitForEventLoop();

        sinon.assert.calledOnceWithExactly(reading, "place-1");

        // What the stream vouched for goes, and the store's rows come in as the store holds them -
        // over what the page carried too, since the place taken up is the store's.
        assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t-vouched"));

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-stored"),
          {
            id: "t-stored",
            title: "stored",
          },
        );

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-carried"),
          {
            id: "t-carried",
            title: "stored",
          },
        );

        assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);

        assert.equal(SyncStream.syncCursor, "place-2");
        assert.isTrue(rendering.calledOnce);
        sinon.assert.calledOnce(LocalDatabase.markAllSynced);
      });

      // Before there was a store to read, it took the state's place and swept every row it held.
      it("takes up the store when it holds no place", async () => {
        const reading = sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [record("t-stored", "stored")],
        });

        SyncStream.syncCursor = null;

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        sinon.assert.calledOnceWithExactly(reading, null);
        assert.equal(SyncStream.syncCursor, "place-2");

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-stored"),
          {
            id: "t-stored",
            title: "stored",
          },
        );
      });

      // A stored record carries only the sets that were filed when it was written.
      it("keeps a set the page filed that the stored row says nothing about", async () => {
        LocalDatabase.replaceFacts("MyApp.Task", "tags", "t-carried", ["g1"]);

        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [
            {...record("t-carried", "stored"), facts: {labels: ["l1"]}},
          ],
        });

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        assert.deepStrictEqual(
          [...LocalDatabase.baseTargetIds("MyApp.Task", "tags", "t-carried")],
          ["g1"],
        );

        assert.deepStrictEqual(
          [...LocalDatabase.baseTargetIds("MyApp.Task", "labels", "t-carried")],
          ["l1"],
        );
      });

      // A write made over a value it just took up would otherwise weigh as older than that value.
      it("sees the revisions of the rows it takes up", async () => {
        const revision = Date.now() * 1024 * 2;

        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [
            {
              facts: {},
              id: "t-stored",
              row: {
                $revisions: {title: revision},
                id: "t-stored",
                title: "stored",
              },
              type: "MyApp.Task",
            },
          ],
        });

        await follow();

        try {
          Tabs.receive(state("place-2"));
          await waitForEventLoop();

          assert.isAbove(Clock.stamp(), revision);
        } finally {
          Clock.reset();
        }
      });

      it("takes a set the stored row names over the one the page filed", async () => {
        LocalDatabase.replaceFacts("MyApp.Task", "tags", "t-carried", ["g1"]);

        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [{...record("t-carried", "stored"), facts: {tags: ["g2"]}}],
        });

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        assert.deepStrictEqual(
          [...LocalDatabase.baseTargetIds("MyApp.Task", "tags", "t-carried")],
          ["g2"],
        );
      });

      // Another user's tab filled the store since: one store serves every user of the browser,
      // each in a group of their own, and nothing in this tab's group would ever bring it there.
      it("leaves the group when another user's tab filled the store", async () => {
        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          owner: "u2",
          records: [record("t-stored", "stored")],
        });

        const detaching = sinon.stub(Durability, "detach");
        const disowning = sinon.stub(Batches, "disown");

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t-stored"));
        assert.isNull(Tabs.name);
        assert.isTrue(detaching.calledOnce);
        assert.isTrue(disowning.calledOnce);
        assert.isNull(SyncStream.syncCursor);
      });

      // A frame gave it the place the state names, so the place alone would send it nowhere, and
      // the state would mark everything complete over rows it never got.
      it("goes back to the store on a state, when its restore found another user's", async () => {
        const reading = sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          owner: "u2",
          records: [record("t-stored", "stored")],
        });

        sinon.stub(Durability, "detach");
        sinon.stub(Batches, "disown");

        const group = nextGroup();

        await holdLeaderLock(group);
        await Tabs.join(group, {onLead: () => {}});

        Tabs.ready(true);

        SyncStream.syncCursor = "place-2";

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        sinon.assert.calledOnce(reading);
        sinon.assert.notCalled(LocalDatabase.markAllSynced);
        assert.isNull(Tabs.name);
      });

      it("passes over a marker until the group has said what its foreign read means", async () => {
        const marker = {cursor: "place-9", scope: "all"};
        const resync = {reason: "somebody else is signed in"};
        const group = nextGroup();

        await holdLeaderLock(group);
        await Tabs.join(group, {onLead: () => {}});

        Tabs.ready(true);

        Tabs.receive({event: "synced", frame: marker, kind: "frame"});

        sinon.assert.notCalled(SyncStream.receiveFrame);

        Tabs.receive({event: "sync_resync", frame: resync, kind: "frame"});
        Tabs.receive({event: "synced", frame: marker, kind: "frame"});

        sinon.assert.calledTwice(SyncStream.receiveFrame);
        sinon.assert.calledWith(SyncStream.receiveFrame, "synced", marker);
      });

      // Leading from a place it never held, it would be told only what changed since.
      it("holds no place a frame names until the group has said what its foreign read means", async () => {
        SyncStream.receiveFrame.callsFake(() => {
          SyncStream.syncCursor = "place-9";
        });

        const group = nextGroup();

        await holdLeaderLock(group);
        await Tabs.join(group, {onLead: () => {}});

        Tabs.ready(true);

        Tabs.receive({
          event: "sync_deltas",
          frame: {cursor: "place-9", deltas: {}},
          kind: "frame",
        });

        assert.isNull(SyncStream.syncCursor);
      });

      // The leader refused that store too, so the whole fill reaches this tab as frames.
      it("stays in the group when a start-over comes before the state", async () => {
        const reading = sinon.stub(Durability, "readBase");

        const group = nextGroup();

        await holdLeaderLock(group);
        await Tabs.join(group, {onLead: () => {}});

        Tabs.ready(true);

        Tabs.receive({
          event: "sync_resync",
          frame: {reason: "somebody else is signed in"},
          kind: "frame",
        });

        Tabs.receive(state(null, {completeness: {all: false, types: []}}));
        await waitForEventLoop();

        sinon.assert.notCalled(reading);
        assert.equal(Tabs.name, group);
      });

      // Leading from nowhere would clear and fill another user's store.
      it("leaves the group when another user's tab filled the store, though handed the lead", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        sinon.stub(Durability, "detach");

        const disowning = sinon.stub(Batches, "disown");
        const led = sinon.spy();
        const {group, release} = await follow({onLead: led});

        Tabs.receive(state("place-2"));

        release();
        await waitForEventLoop();

        // Handed the lead while it reads, or this would be a follower leaving.
        assert.isTrue(Tabs.leader);
        assert.isTrue(Tabs.takingLead);

        read({cursor: "place-2", owner: "u2", records: []});
        await waitForEventLoop();

        assert.isFalse(led.called);
        assert.isTrue(disowning.calledOnce);
        assert.isTrue(await isLockFree(group));
      });

      it("takes up the store its own user's group filled, when signed in", async () => {
        const actor = LocalDatabase.actorUserId;

        LocalDatabase.actorUserId = "u1";

        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          owner: "u1",
          records: [record("t-stored", "stored")],
        });

        try {
          await follow();

          Tabs.receive(state("place-2"));
          await waitForEventLoop();

          assert.deepStrictEqual(
            LocalDatabase.baseRow("MyApp.Task", "t-stored"),
            {
              id: "t-stored",
              title: "stored",
            },
          );

          assert.equal(SyncStream.syncCursor, "place-2");
        } finally {
          LocalDatabase.actorUserId = actor;
        }
      });

      // A stored frame can have landed a batch this tab holds unlanded: promoted again over the
      // rows just taken up, a moved counter would count twice.
      it("takes the landed marks of the batches it holds from the store", async () => {
        Batches.adopt([
          {
            actorUserId: null,
            landed: [],
            seq: 7,
            writes: [
              {id: "t-stored", op: "delete", stamp: 1, type: "MyApp.Task"},
            ],
          },
        ]);

        sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          landed: [{landed: [0], seq: 7}],
          owner: null,
          records: [record("t-stored", "stored")],
        });

        try {
          await follow();

          Tabs.receive(state("place-2"));
          await waitForEventLoop();

          assert.isTrue(Batches.pending[0].isLanded(0));
        } finally {
          Batches.reset();
        }
      });

      // The tab before moved a counter from 1 to 2, stored the frame and the batch's landed mark,
      // and closed before posting either. This tab holds the batch unlanded and the counter at 1,
      // takes up the store, then takes the lead, and the server confirms the batch it sends again.
      it("moves a counter the store already holds moved only once, when it takes the lead after reading the store", async () => {
        globalThis.Hologram.sync.model["MyApp.Task"] = {
          attributes: {count: "integer", id: "uuid"},
          enumValues: {},
          relationships: {},
          serverOnly: [],
        };

        Model.reset();

        sinon.stub(Batches, "flush");

        LocalDatabase.putRow("MyApp.Task", {
          $revisions: {},
          count: 1,
          id: "t1",
        });

        Batches.adopt([
          {
            actorUserId: null,
            landed: [],
            seq: 7,
            writes: [
              {
                deltas: {count: 1},
                id: "t1",
                op: "update",
                stamp: 1_798_246_400_125_952,
                type: "MyApp.Task",
              },
            ],
          },
        ]);

        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        const led = sinon.spy();

        try {
          const {release} = await follow({onLead: led});

          Tabs.receive(state("place-2"));

          release();
          await waitForEventLoop();

          read({
            cursor: "place-2",
            landed: [{landed: [0], seq: 7}],
            owner: null,
            records: [
              {
                facts: {},
                id: "t1",
                row: {$revisions: {}, count: 2, id: "t1"},
                type: "MyApp.Task",
              },
            ],
          });

          await waitForEventLoop();

          assert.isTrue(led.calledOnce);

          const promoting = sinon.spy(Overlay, "promote");

          Batches.settle(7, {dropped: {}, kept: {}, status: "confirmed"});

          // The stored rows already say 2, so the count alone would pass with the batch lost.
          sinon.assert.calledOnce(promoting);

          const [promoted] = promoting.firstCall.args;

          assert.equal(promoted.seq, 7);
          assert.isTrue(promoted.isLanded(0));
          assert.deepStrictEqual(Batches.pending, []);

          assert.equal(LocalDatabase.baseRow("MyApp.Task", "t1").count, 2);
        } finally {
          Batches.reset();
          Clock.reset();
          Model.reset();
        }
      });

      // A completeness claim judges it: the server may no longer send it. So the read leaves it,
      // and the real claim, not a stand-in, is what takes it away.
      it("keeps a row only the page carried, still carried, until a completeness claim", async () => {
        LocalDatabase.markAllSynced.restore();
        LocalDatabase.markTypesSynced.restore();

        const reading = sinon.stub(Durability, "readBase").resolves({
          cursor: "place-2",
          records: [record("t-stored", "stored")],
        });

        await follow();

        Tabs.receive(
          state("place-2", {
            completeness: {all: false, types: []},
            synced: [],
          }),
        );

        await waitForEventLoop();

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-carried"),
          {
            id: "t-carried",
            title: "page",
          },
        );

        assert.deepStrictEqual(LocalDatabase.carriedEntries(), [
          ["MyApp.Task", "t-carried"],
        ]);

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        // At the place it already holds, so the claim is taken without another read.
        sinon.assert.calledOnce(reading);

        assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t-carried"));
        assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-stored"),
          {
            id: "t-stored",
            title: "stored",
          },
        );
      });

      it("holds what arrives while it reads the store, and replays it after", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        const seen = [];

        let arrived;

        const hasArrived = new Promise((resolve) => {
          arrived = resolve;
        });

        const {group} = await follow({
          onMessage: (message) => {
            seen.push(message.kind);

            if (message.kind === "barrier") {
              arrived();
            } else {
              Tabs.receive(message);
            }
          },
        });

        const other = sibling(group);

        other.postMessage(state("place-2"));
        other.postMessage({event: "sync_deltas", frame: {}, kind: "frame"});
        other.postMessage({kind: "barrier"});

        await hasArrived;

        assert.deepStrictEqual(seen, ["state", "barrier"]);
        assert.isFalse(SyncStream.receiveFrame.called);

        read({cursor: "place-2", records: []});
        await waitForEventLoop();

        assert.deepStrictEqual(seen, ["state", "barrier", "frame"]);
        sinon.assert.calledOnceWithExactly(
          SyncStream.receiveFrame,
          "sync_deltas",
          {},
        );
      });

      it("keeps its rows when the store names its own place", async () => {
        sinon
          .stub(Durability, "readBase")
          .resolves({cursor: "place-1", records: null});

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        assert.deepStrictEqual(
          LocalDatabase.baseRow("MyApp.Task", "t-vouched"),
          {
            id: "t-vouched",
            title: "held",
          },
        );

        assert.equal(SyncStream.syncCursor, "place-1");
        assert.isFalse(rendering.called);
        sinon.assert.calledOnce(LocalDatabase.markAllSynced);
      });

      // The leader cleared it to start over: completeness claimed over rows that are going would
      // sweep the ones the refill is about to confirm.
      it("takes no place or completeness when the store names none", async () => {
        sinon
          .stub(Durability, "readBase")
          .resolves({cursor: null, records: null});

        await follow();

        Tabs.receive(state("place-2", {stopReason: "model_hash"}));
        await waitForEventLoop();

        assert.equal(SyncStream.syncCursor, "place-1");
        sinon.assert.notCalled(LocalDatabase.markAllSynced);
        sinon.assert.notCalled(LocalDatabase.markTypesSynced);

        sinon.assert.calledOnceWithExactly(
          SyncStream.receiveFrame,
          "sync_reload",
          {
            reason: "model_hash",
          },
        );
      });

      // Nothing says which rows stand at the group's place, and the next frame naming one would
      // hand it over anyway - so it leaves, as a tab whose store cannot be read at boot does.
      it("leaves the group when the store cannot be read", async () => {
        sinon.stub(Durability, "readBase").resolves(null);

        const detaching = sinon.stub(Durability, "detach");
        const disowning = sinon.stub(Batches, "disown");
        const reconnecting = sinon.stub(Sse, "reconnect");
        const refreshing = sinon.stub(Replica, "refresh");
        const wasStarted = Sse.isStarted;

        Sse.isStarted = true;

        try {
          await follow();

          Tabs.receive(state("place-2"));
          await waitForEventLoop();

          assert.isNull(Tabs.name);
          assert.isTrue(Tabs.leader);
          assert.isTrue(detaching.calledOnce);
          assert.isTrue(disowning.calledOnce);
          assert.isTrue(refreshing.calledOnce);

          // A stream of its own, greeting the server from nowhere: the place it holds is in doubt.
          assert.isTrue(reconnecting.calledOnce);

          assert.isNull(SyncStream.syncCursor);
          sinon.assert.notCalled(LocalDatabase.markAllSynced);
        } finally {
          Sse.isStarted = wasStarted;
        }
      });

      // Told after leaving, the message would go nowhere, and the group's leader would send the
      // write only when something else woke it.
      it("leaves the group only once the writes it is still saving are told to the group", async () => {
        let saved;

        sinon.stub(Durability, "readBase").resolves(null);
        sinon.stub(Durability, "detach");
        sinon.stub(Batches, "disown");

        const saving = sinon
          .stub(Batches, "recorded")
          .returns(new Promise((resolve) => (saved = resolve)));

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        assert.isTrue(saving.calledOnce);
        assert.isNotNull(Tabs.name);

        saved();
        await waitForEventLoop();

        assert.isNull(Tabs.name);
      });

      // What it holds is its own by then, batches included, and leaving again would drop them.
      it("leaves alone a tab that left the group while its writes were being saved", async () => {
        let saved;

        sinon.stub(Durability, "readBase").resolves(null);

        const detaching = sinon.stub(Durability, "detach");
        const disowning = sinon.stub(Batches, "disown");

        sinon
          .stub(Batches, "recorded")
          .returns(new Promise((resolve) => (saved = resolve)));

        await follow();

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        await Tabs.leave();

        saved();
        await waitForEventLoop();

        assert.isTrue(Tabs.leader);
        assert.isFalse(detaching.called);
        assert.isFalse(disowning.called);
      });

      // It holds the lock, so it keeps the queue; but its stream is a follower's, and the place it
      // was checking is the one in doubt. It takes no lead in a group that has ended.
      it("opens a stream of its own from nowhere when the group ends while it reads with the lead", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        sinon.stub(Durability, "detach");

        const disowning = sinon.stub(Batches, "disown");
        const reconnecting = sinon.stub(Sse, "reconnect");
        const led = sinon.spy();
        const wasStarted = Sse.isStarted;

        Sse.isStarted = true;

        try {
          const {release} = await follow({onLead: led});

          Tabs.receive(state("place-2"));

          release();
          await waitForEventLoop();

          Tabs.receive({kind: "storage_failed"});

          read({cursor: "place-2", records: []});
          await waitForEventLoop();

          assert.isNull(Tabs.name);
          assert.isNull(SyncStream.syncCursor);
          assert.isTrue(reconnecting.calledOnce);
          assert.isFalse(disowning.called);
          assert.isFalse(led.called);
        } finally {
          Sse.isStarted = wasStarted;
        }
      });

      // A stream reconnecting meanwhile would greet the server with sync from the place the read
      // is checking. The lead's own reconnect greets from the place it settles on.
      it("is served no sync while it holds a lead it was handed during the read", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        let settling;

        const led = sinon.spy(() => (settling = Tabs.takingLead));
        const {release} = await follow({onLead: led});

        Tabs.receive(state("place-2"));

        release();
        await waitForEventLoop();

        assert.isTrue(Tabs.leader);
        assert.isTrue(Tabs.takingLead);

        read({cursor: "place-2", records: []});
        await waitForEventLoop();

        assert.isTrue(led.calledOnce);
        assert.isFalse(settling);
      });

      // Leaving would let go of the lock, and with nobody waiting for it nobody would send the queue.
      it("starts over as the leader when it was handed the lead while its writes were saved", async () => {
        let saved;

        sinon.stub(Durability, "readBase").resolves(null);

        const detaching = sinon.stub(Durability, "detach");

        sinon
          .stub(Batches, "recorded")
          .returns(new Promise((resolve) => (saved = resolve)));

        const led = sinon.spy();
        const {group, release} = await follow({onLead: led});

        Tabs.receive(state("place-2"));
        await waitForEventLoop();

        release();
        await waitForEventLoop();

        saved();
        await waitForEventLoop();

        assert.isTrue(led.calledOnce);
        assert.isNull(SyncStream.syncCursor);
        assert.isFalse(detaching.called);
        assert.isFalse(await isLockFree(group));
      });

      it("starts over as the leader when it was handed the lead while a read failed", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        const detaching = sinon.stub(Durability, "detach");
        const disowning = sinon.stub(Batches, "disown");

        let placed;

        const led = sinon.spy(() => (placed = SyncStream.syncCursor));
        const {group, release} = await follow({onLead: led});

        Tabs.receive(state("place-2"));

        release();
        await waitForEventLoop();

        read(null);
        await waitForEventLoop();

        // From nowhere: leaving would let go of the lock with nobody waiting for it.
        assert.isTrue(led.calledOnce);
        assert.isNull(placed);
        assert.equal(Tabs.name, group);
        assert.isFalse(detaching.called);
        assert.isFalse(disowning.called);
        assert.isFalse(await isLockFree(group));
      });

      // Not ready, it would hold everything its group says for the rest of its life.
      it("is ready again when taking up the store fails", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        rendering.throws(new Error("refused"));

        // The failure goes where any uncaught one does, which here is the test runner's.
        const listeners = process.listeners("unhandledRejection");
        const rejected = [];

        process.removeAllListeners("unhandledRejection");
        process.on("unhandledRejection", (error) => rejected.push(error));

        const seen = [];

        let arrived;

        const hasArrived = new Promise((resolve) => (arrived = resolve));

        try {
          const {group} = await follow({
            onMessage: (message) => {
              seen.push(message.kind);

              if (message.kind === "barrier") {
                arrived();
              } else {
                Tabs.receive(message);
              }
            },
          });

          const other = sibling(group);

          other.postMessage(state("place-2"));
          await waitForEventLoop();

          other.postMessage({event: "sync_deltas", frame: {}, kind: "frame"});
          other.postMessage({kind: "barrier"});

          await hasArrived;

          // Held while the read is out, past a message that is not: it is the replay that brings
          // the frame.
          assert.deepStrictEqual(seen, ["state", "barrier"]);

          read({cursor: "place-2", records: []});
          await waitForEventLoop();
        } finally {
          process.removeAllListeners("unhandledRejection");
          listeners.forEach((listener) =>
            process.on("unhandledRejection", listener),
          );
        }

        assert.deepStrictEqual(seen, ["state", "barrier", "frame"]);
        assert.deepStrictEqual(
          rejected.map((error) => error.message),
          ["refused"],
        );
      });

      it("takes a lead handed to it while it read the store", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        const led = sinon.spy();
        const {release} = await follow({onLead: led});

        Tabs.receive(state("place-2"));

        release();
        await waitForEventLoop();

        assert.isTrue(Tabs.leader);
        assert.isFalse(led.called);

        read({cursor: "place-2", records: []});
        await waitForEventLoop();

        assert.isTrue(led.calledOnce);
        assert.equal(SyncStream.syncCursor, "place-2");
      });

      it("leaves a store it read after leaving the group alone", async () => {
        let read;

        sinon
          .stub(Durability, "readBase")
          .returns(new Promise((resolve) => (read = resolve)));

        await follow();

        Tabs.receive(state("place-2"));

        await Tabs.leave();

        read({cursor: "place-2", records: [record("t-stored", "stored")]});
        await waitForEventLoop();

        assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t-stored"));
        assert.equal(SyncStream.syncCursor, "place-1");
        sinon.assert.notCalled(LocalDatabase.markAllSynced);
      });

      it("takes a state naming its own place without reading the store", async () => {
        const reading = sinon.stub(Durability, "readBase");

        await follow();

        Tabs.receive(state("place-1"));

        assert.isFalse(reading.called);
        sinon.assert.calledOnce(LocalDatabase.markAllSynced);
      });

      // The leader is starting over, and the start-over that follows says so.
      it("takes a state naming no place without reading the store", async () => {
        const reading = sinon.stub(Durability, "readBase");

        await follow();

        Tabs.receive(state(null));

        assert.isFalse(reading.called);
        assert.equal(SyncStream.syncCursor, "place-1");
      });

      // Handed the lead while starting, it brings the store to its own memory as it takes it.
      it("takes a state naming another place without reading the store, when it leads", async () => {
        const reading = sinon.stub(Durability, "readBase");
        const group = nextGroup();
        const release = await holdLeaderLock(group);

        let arrived;

        const hasArrived = new Promise((resolve) => (arrived = resolve));

        await Tabs.join(group, {
          onLead: () => {},
          onMessage: (message) =>
            message.kind === "barrier" ? arrived() : Tabs.receive(message),
        });

        const other = sibling(group);

        other.postMessage(state("place-2"));
        other.postMessage({kind: "barrier"});

        await hasArrived;

        release();
        await waitForEventLoop();

        assert.isTrue(Tabs.leader);

        Tabs.ready();

        assert.isFalse(reading.called);
        assert.equal(SyncStream.syncCursor, "place-1");
        sinon.assert.calledOnce(LocalDatabase.markAllSynced);
      });
    });
  });

  describe("join()", () => {
    it("leads when nobody holds the group's lock", async () => {
      assert.isTrue(await Tabs.join(nextGroup(), stubs()));
      assert.isTrue(Tabs.leader);
    });

    // What it holds before it is ready is its page's identity and no place, not what the store
    // gave it (see ready()).
    it("says nothing to a group it has just taken the lead of", async () => {
      const posting = sinon.stub(Tabs, "post");

      await Tabs.join(nextGroup(), stubs());

      assert.isFalse(posting.called);
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

      sibling(group).postMessage({kind: "barrier"});

      assert.deepStrictEqual(await hasReceived, {kind: "barrier"});
    });
  });

  // What a tab does when its page follows the session to another user (see
  // DataLayer.followIdentity).
  describe("move()", () => {
    it("stays in no group when the tab is in none", async () => {
      assert.isNull(await Tabs.move(nextGroup()));
      assert.isNull(Tabs.name);
    });

    it("leaves the group it was in for the one it is given", async () => {
      const from = nextGroup();
      const to = nextGroup();

      await Tabs.join(from, stubs());

      await Tabs.move(to);

      assert.equal(Tabs.name, to);
      assert.isTrue(await isLockFree(from));
      assert.isFalse(await isLockFree(to));
      assert.isTrue(Tabs.leader);
    });

    it("answers the visit to the new group", async () => {
      await Tabs.join(nextGroup(), stubs());

      const visit = await Tabs.move(nextGroup());

      assert.isTrue(Tabs.isVisit(visit));

      Tabs.leave();

      assert.isFalse(Tabs.isVisit(visit));
    });

    it("answers nothing when a newer move took the tab elsewhere while it joined", async () => {
      await Tabs.join(nextGroup(), stubs());

      const first = Tabs.move(nextGroup());
      const second = Tabs.move(nextGroup());

      assert.isNull(await first);
      assert.isTrue(Tabs.isVisit(await second));
    });

    // The handlers are the page's, and there is no page to name them again.
    it("keeps what the tab does with the group's messages", async () => {
      const to = nextGroup();
      const received = [];

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => received.push(message),
      });

      await holdLeaderLock(to);
      await Tabs.move(to);

      Tabs.ready();

      sibling(to).postMessage({kind: "joined"});
      await waitForEventLoop();

      assert.deepStrictEqual(received, [{kind: "joined"}]);
    });

    // Until the tab has read the new group's store, a frame its stream stored would land under a
    // claim it hasn't judged.
    it("settles where the tab starts from before its stream is served sync", async () => {
      await Tabs.join(nextGroup(), stubs());

      await Tabs.move(nextGroup());

      assert.isTrue(Tabs.takingLead);

      Tabs.ready();

      assert.isFalse(Tabs.takingLead);
    });

    // A handshake answered while the tab joins mustn't take it for a tab that sends for itself (see
    // DataLayer.takeHandshake).
    it("is settling a start from the moment it moves", async () => {
      await Tabs.join(nextGroup(), stubs());

      const moving = Tabs.move(nextGroup());

      assert.isTrue(Tabs.takingLead);

      await moving;
    });

    it("settles a follower's start the same way", async () => {
      const to = nextGroup();

      await Tabs.join(nextGroup(), stubs());

      await holdLeaderLock(to);
      await Tabs.move(to);

      assert.isFalse(Tabs.leader);
      assert.isTrue(Tabs.takingLead);

      Tabs.ready();

      assert.isFalse(Tabs.takingLead);
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
    const barrier = {kind: "barrier"};

    it("holds frames until the tab is ready and drains them in order", async () => {
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      // A tab that follows: one that leads with no place drops both (see below).
      const group = nextGroup();

      await holdLeaderLock(group);

      await Tabs.join(group, {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
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

      // A tab that follows: one that leads with no place drops both (see below).
      const group = nextGroup();

      await holdLeaderLock(group);

      await Tabs.join(group, {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
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

          if (message.kind === "barrier") {
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

    // A filed batch lands on a queue the store has not handed over yet: before the mount it is
    // passed over for a signed-in user, and in a tab that leads it wakes the sender.
    it("holds a batch another tab filed until the tab is ready", async () => {
      const sealed = {kind: "sealed", record: {seq: 3}};
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage(sealed);
      other.postMessage(barrier);

      await hasArrived;

      assert.deepStrictEqual(seen, [barrier]);

      Tabs.ready();

      assert.deepStrictEqual(seen, [barrier, sealed]);
    });

    // The answer names an identity and a place, which a starting tab holds only once its restore
    // has handed it the ones the store had. Ready, it says what it holds once for every tab that
    // asked, rather than once per request.
    it("answers a request for the state once it is ready, when it leads", async () => {
      const seen = [];

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const posting = sinon.stub(Tabs, "post");
      const other = sibling(Tabs.name);

      other.postMessage({kind: "joined"});
      other.postMessage({kind: "joined"});
      other.postMessage(barrier);

      await hasArrived;

      assert.isFalse(posting.called);

      Tabs.ready();

      assert.deepStrictEqual(seen, [barrier]);
      assert.isTrue(posting.calledOnce);
      assert.equal(posting.firstCall.args[0].kind, "state");
    });

    it("says what it holds once it is ready, when it leads", async () => {
      await Tabs.join(nextGroup(), stubs());

      const posting = sinon.stub(Tabs, "post");

      Tabs.ready();

      assert.isTrue(posting.calledOnce);
      assert.equal(posting.firstCall.args[0].kind, "state");
    });

    it("says nothing once it is ready, when it follows", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());

      const posting = sinon.stub(Tabs, "post");

      Tabs.ready();

      assert.isFalse(posting.called);
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

      sibling(Tabs.name).postMessage({kind: "storage_failed"});

      await hasArrived;

      assert.deepStrictEqual(seen, [{kind: "storage_failed"}]);
    });

    // The tab before it closed while this one joined, with nobody else waiting for the lock: what it
    // said is the tail of a fill this tab's restore refused the head of, as for a lead handed over.
    it("drops what the tab before it said and takes no identity from it, when it joined as the leader with no place", async () => {
      const answered = {answer: "ok", kind: "answered", seq: 3};
      const persisting = sinon.stub(Durability, "persistReplica").resolves();
      const seen = [];

      sinon.stub(Tabs, "postState");

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage(frame(1));

      other.postMessage({
        completeness: {all: true, types: []},
        cursor: "place-9",
        kind: "state",
        replica: {id: "r-group", token: "statement-group"},
        synced: ["all"],
      });

      other.postMessage(answered);
      other.postMessage(barrier);

      await hasArrived;

      try {
        Tabs.ready();

        assert.deepStrictEqual(seen, [barrier, answered]);

        // It read the store after that tab let go, so after that tab wrote its identity down.
        assert.isNull(Replica.id);
        assert.isFalse(persisting.called);
      } finally {
        Replica.reset();
      }
    });

    // It read the store after the tab before it let go of the lock, so after that tab wrote its
    // identity down - and the state can name an older one. The frames stay, in order, so the frame
    // that landed a batch marks it before the answer to it promotes anything.
    it("replays the frames but no state the tab before it said, when it joined as the leader with a place", async () => {
      const persisting = sinon.stub(Durability, "persistReplica").resolves();
      const seen = [];

      const messages = [
        {kind: "sealed", record: {seq: 4}},
        {event: "sync_resync", frame: {reason: "identity"}, kind: "frame"},
        frame(1),
        {
          completeness: {all: true, types: []},
          cursor: "place-9",
          kind: "state",
          replica: {id: "r-group", token: "statement-group"},
          synced: ["all"],
        },
        {answer: "ok", kind: "answered", seq: 4},
      ];

      sinon.stub(Tabs, "postState");

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          seen.push(message);

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      for (const message of messages) {
        other.postMessage(message);
      }

      other.postMessage(barrier);

      await hasArrived;

      try {
        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.deepStrictEqual(seen, [
          barrier,
          messages[0],
          messages[1],
          messages[2],
          messages[4],
        ]);

        assert.isNull(Replica.id);
        assert.isFalse(persisting.called);
      } finally {
        Replica.reset();
        SyncStream.syncCursor = null;
      }
    });

    // The tab before it moved a counter, the server applied it, and that tab stored the frame and
    // closed: this tab's store already holds the move. Replayed, the frame marks the batch landed
    // before the answer promotes it, so the move is not added a second time.
    it("moves a counter the tab before it already moved only once, when it joined as the leader with a place", async () => {
      globalThis.Hologram.sync = {
        model: {
          "MyApp.Task": {
            attributes: {count: "integer", id: "uuid"},
            enumValues: {},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();

      // Nobody is signed in, as the batch says: a page takes up only its own user's batches, and
      // the user is not reset between files.
      const actor = LocalDatabase.actorUserId;

      LocalDatabase.actorUserId = null;

      sinon.stub(Batches, "flush");
      sinon.stub(SyncStream, "scheduleRender");

      const promoting = sinon.spy(Overlay, "promote");
      sinon.stub(Tabs, "postState");

      // What the store holds, and this tab restored: the server's row with the move in it.
      LocalDatabase.putRow("MyApp.Task", {$revisions: {}, count: 1, id: "t1"});

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) =>
          message.kind === "barrier" ? arrived() : Tabs.receive(message),
      });

      const other = sibling(Tabs.name);

      other.postMessage({
        kind: "sealed",
        record: {
          actorUserId: null,
          landed: [],
          seq: 1,
          writes: [
            {
              deltas: {count: 1},
              id: "t1",
              op: "update",
              stamp: 1_798_246_400_125_952,
              type: "MyApp.Task",
            },
          ],
        },
      });

      other.postMessage({
        event: "sync_deltas",
        frame: {
          applied_seq: 1,
          cursor: "place-2",
          deltas: {patch_entity: {"MyApp.Task": [{count: 1, id: "t1"}]}},
        },
        kind: "frame",
      });

      other.postMessage({
        answer: {dropped: {}, kept: {}, status: "confirmed"},
        kind: "answered",
        seq: 1,
      });

      other.postMessage(barrier);

      await hasArrived;

      try {
        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.equal(LocalDatabase.baseRow("MyApp.Task", "t1").count, 1);
        assert.deepStrictEqual(Batches.pending, []);

        // Promoted, and landed by then.
        sinon.assert.calledOnce(promoting);
        assert.isTrue(promoting.firstCall.args[0].isLanded(0));
      } finally {
        Batches.reset();
        Clock.reset();
        LocalDatabase.reset();
        LocalDatabase.actorUserId = actor;
        Model.reset();
        SyncStream.syncCursor = null;
      }
    });

    // Nothing else prompts the first tab to say what it holds before its stream first serves it.
    it("says what it holds when one message it held cannot be taken, when it leads", async () => {
      const stating = sinon.stub(Tabs, "postState");

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(nextGroup(), {
        onLead: () => {},
        onMessage: (message) => {
          if (message.kind === "answered") {
            throw new Error("refused");
          }

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const other = sibling(Tabs.name);

      other.postMessage({answer: "ok", kind: "answered", seq: 3});
      other.postMessage(barrier);

      await hasArrived;

      const listeners = process.listeners("uncaughtException");
      const failures = [];

      process.removeAllListeners("uncaughtException");
      process.on("uncaughtException", (error) => failures.push(error));

      try {
        Tabs.ready();
        await waitForEventLoop();
      } finally {
        process.removeAllListeners("uncaughtException");

        listeners.forEach((listener) =>
          process.on("uncaughtException", listener),
        );
      }

      assert.isTrue(stating.calledOnce);
      assert.equal(failures.length, 1);
    });

    // What it held is gone from the queue of held messages by then, and a lead not taken leaves the
    // group with nobody sending.
    it("replays the rest and takes the lead when one message it held cannot be taken", async () => {
      const group = nextGroup();
      const release = await holdLeaderLock(group);
      const seen = [];
      const led = sinon.spy(() => seen.push("lead"));

      let arrived;

      const hasArrived = new Promise((resolve) => {
        arrived = resolve;
      });

      await Tabs.join(group, {
        onLead: led,
        onMessage: (message) => {
          if (message.frame === 1) {
            throw new Error("refused");
          }

          seen.push(message);

          if (message.kind === "barrier") {
            arrived();
          }
        },
      });

      const other = sibling(group);

      other.postMessage(frame(1));
      other.postMessage(frame(2));
      other.postMessage(barrier);

      await hasArrived;

      release();
      await waitForEventLoop();

      // Reported the way any uncaught failure is, which here is the test runner's way.
      const listeners = process.listeners("uncaughtException");
      const failures = [];

      process.removeAllListeners("uncaughtException");
      process.on("uncaughtException", (error) => failures.push(error));

      try {
        SyncStream.syncCursor = "place-1";

        Tabs.ready();
        await waitForEventLoop();
      } finally {
        process.removeAllListeners("uncaughtException");

        listeners.forEach((listener) =>
          process.on("uncaughtException", listener),
        );

        SyncStream.syncCursor = null;
      }

      // The rest first: the lead repairs the store from the rows and the place the replay leaves.
      assert.deepStrictEqual(seen, [barrier, frame(2), "lead"]);
      assert.isTrue(led.calledOnce);
      assert.deepStrictEqual(
        failures.map((error) => error.message),
        ["refused"],
      );
    });

    // What follows the state is about what the read brings, so applied during the read it would be
    // overwritten by it.
    it("stops replaying at a state that sends it back to the store, and replays the rest after", async () => {
      let read;

      sinon
        .stub(Durability, "readBase")
        .returns(new Promise((resolve) => (read = resolve)));

      sinon.stub(LocalDatabase, "markAllSynced");
      sinon.stub(LocalDatabase, "markTypesSynced");
      sinon.stub(SyncStream, "receiveFrame");
      sinon.stub(SyncStream, "scheduleRender");

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
          seen.push(message.kind);

          if (message.kind === "barrier") {
            arrived();
          } else {
            Tabs.receive(message);
          }
        },
      });

      const other = sibling(group);

      other.postMessage({
        completeness: {all: false, types: []},
        cursor: "place-2",
        kind: "state",
        replica: {id: null, token: null},
        synced: [],
      });

      other.postMessage(frame(1));
      other.postMessage(barrier);

      await hasArrived;

      // Nobody is signed in, as the store says: a tab takes up only its own user's store.
      const actor = LocalDatabase.actorUserId;

      LocalDatabase.actorUserId = null;

      try {
        SyncStream.syncCursor = "place-1";

        Tabs.ready();

        assert.deepStrictEqual(seen, ["barrier", "state"]);

        read({cursor: "place-2", owner: null, records: []});
        await waitForEventLoop();

        assert.deepStrictEqual(seen, ["barrier", "state", "frame"]);
      } finally {
        LocalDatabase.reset();
        LocalDatabase.actorUserId = actor;
        SyncStream.syncCursor = null;
      }
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

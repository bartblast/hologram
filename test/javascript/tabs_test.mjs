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
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Replica from "../../assets/js/replica.mjs";
import Sse from "../../assets/js/sse.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

// Without this the file passes only when something else in the run has installed sessionStorage
// first: a browser that cannot coordinate its tabs is told so through Logger, which writes there.
registerWebApis();

// Hologram.currentPageModule() answers a boxed module, and reading its name goes through the
// interpreter - so the runtime globals have to be there before a page-scoped message is judged.
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

  beforeEach(() => {
    openChannels = [];
    releases = [];
  });

  afterEach(async () => {
    await Tabs.leave();

    releases.forEach((release) => release());
    openChannels.forEach((channel) => channel.close());

    sinon.restore();
  });

  // What a tab does when the store it was sharing is gone: the group is over, and every tab goes
  // back to being a replica of its own.
  describe("dissolve()", () => {
    let disowning, reconnecting;

    beforeEach(() => {
      disowning = sinon.stub(Batches, "disown");
      reconnecting = sinon.stub(Sse, "reconnect");

      Replica.offer({id: "r-fresh", token: "statement-fresh"});
    });

    afterEach(() => {
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
  });

  // What a tab does the moment the group becomes its to lead, with nothing handed over by the tab
  // that was leading - which may have closed without warning.
  describe("taking the lead", () => {
    let clearing, flushing, reconnecting, repairing;

    // Takes the group's lock, hands this tab the follower's place in the queue behind it, and
    // answers what makes the tab lead. Waits for the lead to be taken, so what follows is settled.
    const succeed = async (group) => {
      const release = await holdLeaderLock(group);

      await Tabs.join(group, {});

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
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;

      LocalDatabase.reset();
      Model.reset();

      Sse.syncCursor = null;
    });

    it("opens a stream of its own and starts sending", async () => {
      Sse.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isTrue(Tabs.leader);
      assert.isTrue(reconnecting.calledOnce);
      assert.isTrue(flushing.calledOnce);
      assert.isTrue(Tabs.postState.calledOnce);
    });

    // The store is written without waiting, so the tab that was leading can have posted a frame and
    // closed before its write landed - and carrying on would leave a place naming rows nothing
    // holds.
    it("brings the store up to what it holds, when it has a place", async () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "from the stream"});

      Sse.syncCursor = "place-1";

      await succeed(nextGroup());

      assert.isTrue(repairing.calledOnce);

      assert.deepStrictEqual(repairing.firstCall.args[1], "place-1");

      assert.deepStrictEqual(
        repairing.firstCall.args[0].map((record) => record.id),
        ["t1"],
      );

      assert.isFalse(clearing.called);
    });

    it("starts over when it has no place to resume from", async () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "from the stream"});

      const posting = sinon.stub(Tabs, "post");

      await succeed(nextGroup());

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.isTrue(clearing.calledOnce);
      assert.isFalse(repairing.called);

      assert.deepStrictEqual(posting.firstCall.args[0], {
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    });
  });

  describe("postState()", () => {
    afterEach(() => {
      GlobalRegistry.set("connectPageModule", null);

      LocalDatabase.reset();
      Replica.reset();

      Sse.syncCursor = null;
    });

    // The three things a joining tab cannot read out of the store: the scopes, which nothing writes
    // down, and the place and the identity as they stand now.
    it("says what this tab knows that the store cannot tell", () => {
      const posting = sinon.stub(Tabs, "post");

      GlobalRegistry.set("connectPageModule", "MyApp.TodosPage");
      LocalDatabase.markSynced("page");
      Replica.offer({id: "r-group", token: "statement-group"});

      Sse.syncCursor = "place-1";

      Tabs.postState();

      assert.deepStrictEqual(posting.firstCall.args[0], {
        cursor: "place-1",
        kind: "state",
        page: "MyApp.TodosPage",
        replica: {id: "r-group", token: "statement-group"},
        synced: ["page"],
      });
    });
  });

  describe("receive()", () => {
    const PAGE = "MyApp.TodosPage";

    // The page a message names is the page the STREAM was greeted with, and what this tab does
    // with a page-scoped claim depends on whether it is the page this tab is on.
    const mountPage = (name) =>
      sinon
        .stub(Hologram, "currentPageModule")
        .returns(name === null ? null : Type.alias(name));

    beforeEach(() => {
      sinon.stub(Sse, "receiveFrame");
      sinon.stub(LocalDatabase, "markSynced");

      mountPage(PAGE);
    });

    afterEach(() => {
      LocalDatabase.reset();
      Replica.reset();
      Sse.syncCursor = null;
    });

    it("applies a frame to this tab's own memory", () => {
      const frame = {applied_seq: null, cursor: "place-1", deltas: {}};

      Tabs.receive({event: "sync_deltas", frame, kind: "frame"});

      assert.isTrue(
        Sse.receiveFrame.calledOnceWithExactly("sync_deltas", frame),
      );
    });

    it("applies a completeness marker for the page this tab is on", () => {
      Tabs.receive({
        event: "synced",
        frame: {cursor: "place-1", scope: "page"},
        kind: "frame",
        page: PAGE,
      });

      assert.isTrue(Sse.receiveFrame.calledOnce);
    });

    // The claim is that the page the stream was greeted with can be answered from what the client
    // holds - which says nothing about a tab sitting on another page.
    it("passes over a completeness marker for a page this tab is not on", () => {
      Tabs.receive({
        event: "synced",
        frame: {cursor: "place-1", scope: "page"},
        kind: "frame",
        page: "MyApp.SettingsPage",
      });

      assert.isFalse(Sse.receiveFrame.called);
    });

    it("applies a whole-app completeness marker whatever page this tab is on", () => {
      Tabs.receive({
        event: "synced",
        frame: {cursor: "place-1", scope: "all"},
        kind: "frame",
        page: "MyApp.SettingsPage",
      });

      assert.isTrue(Sse.receiveFrame.calledOnce);
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

    it("answers a tab that has joined with nothing, when it follows", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, {onLead: () => {}});

      const posting = sinon.stub(Tabs, "post");

      Tabs.receive({kind: "joined"});

      assert.isFalse(posting.called);
    });

    it("takes the identity, the place and the scopes from the group's state", () => {
      Tabs.receive({
        cursor: "place-1",
        kind: "state",
        page: PAGE,
        replica: {id: "r-group", token: "statement-group"},
        synced: ["all", "page"],
      });

      assert.equal(Replica.id, "r-group");
      assert.equal(Sse.syncCursor, "place-1");

      assert.deepStrictEqual(
        LocalDatabase.markSynced.args.map(([scope]) => scope),
        ["all", "page"],
      );
    });

    // Its own reading has already brought it further, or to somewhere else entirely.
    it("keeps a place it already holds", () => {
      Sse.syncCursor = "place-2";

      Tabs.receive({
        cursor: "place-1",
        kind: "state",
        page: PAGE,
        replica: {id: null, token: null},
        synced: [],
      });

      assert.equal(Sse.syncCursor, "place-2");
    });

    it("takes no scope for a page this tab is not on", () => {
      Tabs.receive({
        cursor: null,
        kind: "state",
        page: "MyApp.SettingsPage",
        replica: {id: null, token: null},
        synced: ["page"],
      });

      assert.isFalse(LocalDatabase.markSynced.called);
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

      release();
      await hasLed;

      assert.isTrue(Tabs.leader);
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

    it("hands a frame straight through once the tab is ready", async () => {
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
        page: null,
        replica: {id: null, token: null},
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

    it("says nothing outside a group", () => {
      assert.doesNotThrow(() => Tabs.post({kind: "joined"}));
    });
  });
});

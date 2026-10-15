"use strict";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import Durability from "../../assets/js/durability.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Replica from "../../assets/js/replica.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// Every handler here that logs - a resync, a reload notice - writes to sessionStorage through
// Logger, so the file installs it itself rather than leaning on whatever ran before it.
registerWebApis();

describe("SyncStream", () => {
  let animationFrames;
  let eventSource;
  let originalWindow;

  beforeEach(() => {
    SyncStream.renderScheduled = false;
    SyncStream.syncCursor = null;

    // Level, which is what "not mid-navigation" is - the state a repaint is allowed to run in.
    // Reset here rather than by the one test that parts them, so a failing assertion cannot leave
    // every test after it looking mid-navigation.
    Hologram.domEpoch = 0;
    Hologram.registryEpoch = 0;

    LocalDatabase.reset();
    Model.reset();

    originalWindow = globalThis.window;

    // The scheduled repaint is captured rather than run: what a test asserts is that ONE was
    // asked for, and running it here would drag a whole render into a stream test.
    animationFrames = [];

    globalThis.window = {
      location: {reload: sinon.spy()},
      requestAnimationFrame: (callback) => animationFrames.push(callback),
    };

    // A stream the sync listeners are added to, standing in for the EventSource the realtime
    // stream opens: each test calls the listener for the kind it delivers.
    eventSource = {
      addEventListener(type, listener) {
        this.listeners[type] = listener;
      },
      listeners: {},
    };

    SyncStream.listen(eventSource);
  });

  // Everything a frame can leave behind, so no file that runs after this one starts mid-repaint, on
  // a stale-bundle notice, or connected to a page.
  afterEach(() => {
    sinon.restore();

    globalThis.window = originalWindow;

    GlobalRegistry.set("connectPageModule", null);
    GlobalRegistry.set("syncStaleReason", null);
    SyncStream.renderScheduled = false;
    SyncStream.syncCursor = null;
  });

  // What a refill does to writes this client has made and not had answered. Every case is one the
  // design had to be written out for, because a resync is where the two halves of the seam meet:
  // the base is being replaced wholesale while the overlay goes on folding over it.
  describe("a refill over pending writes", () => {
    const TASK = "MyApp.Task";

    const deltasFrame = (rows) =>
      JSON.stringify({
        applied_seq: null,
        cursor: null,
        deltas: {put_entity: {[TASK]: rows}},
        model_hash: "a3f9c2",
        protocol_version: 1,
      });

    const resyncFrame = () =>
      JSON.stringify({protocol_version: 1, reason: "retention"});

    const syncedFrame = () =>
      JSON.stringify({protocol_version: 1, scope: "all"});

    // A batch of this client's own, sealed and waiting for an answer.
    const pending = (write) => {
      Batches.open("tasks");
      Batches.current().append(write);

      return Batches.close();
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
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
        modelHash: "a3f9c2",
        protocolVersion: 1,
      };

      Model.reset();
    });

    afterEach(() => {
      Batches.reset();
      Model.reset();

      delete globalThis.Hologram.sync;
    });

    // The base takes the server's copy and the pending edit still shows on top of it, which is
    // the ordinary overlay rule reaching across a resync unchanged.
    it("folds a pending update over the row the refill delivered", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "before the resync"});

      pending({
        data: {title: "mine"},
        id: "t1",
        op: "update",
        stamp: 1,
        type: TASK,
      });

      eventSource.listeners.sync_resync({data: resyncFrame()});

      // Before a single row of the refill has landed: the write still has something to fold over,
      // which is what an action reading its own edit mid-refill depends on.
      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "mine");

      eventSource.listeners.sync_deltas({
        data: deltasFrame([{id: "t1", title: "from the server"}]),
      });

      eventSource.listeners.synced({data: syncedFrame()});

      assert.equal(LocalDatabase.baseRow(TASK, "t1").title, "from the server");
      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "mine");
    });

    // A create answered while the refill was still running is in the base as the SERVER's row,
    // filed by the promotion rather than delivered by a frame - so nothing marked it, and the
    // sweep has no reason to take it.
    it("keeps a create confirmed while the refill ran", () => {
      const batch = pending({
        data: {title: "made here"},
        id: "t2",
        op: "create",
        stamp: 1024,
        type: TASK,
      });

      eventSource.listeners.sync_resync({data: resyncFrame()});

      Overlay.promote(batch, null);

      eventSource.listeners.synced({data: syncedFrame()});

      assert.equal(LocalDatabase.getRow(TASK, "t2").title, "made here");
    });

    // A row the base never held cannot be marked and cannot be swept: it is on the screen because
    // the overlay puts it there, and it stays until the server rules on it.
    it("keeps a create still pending across the marker", () => {
      pending({
        data: {title: "made here"},
        id: "t2",
        op: "create",
        stamp: 1024,
        type: TASK,
      });

      eventSource.listeners.sync_resync({data: resyncFrame()});
      eventSource.listeners.synced({data: syncedFrame()});

      assert.equal(LocalDatabase.getRow(TASK, "t2").title, "made here");
      assert.isNull(LocalDatabase.baseRow(TASK, "t2"));
    });

    // A second resync arriving part way through the first one's refill puts the rows it had
    // already delivered back to awaiting - otherwise a row delivered by the abandoned fill would
    // outlive one that no longer sends it.
    it("marks a row again when a second resync arrives mid-refill", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "before the resync"});

      eventSource.listeners.sync_resync({data: resyncFrame()});

      eventSource.listeners.sync_deltas({
        data: deltasFrame([{id: "t1", title: "from the first refill"}]),
      });

      eventSource.listeners.sync_resync({data: resyncFrame()});

      // Delivered by the first refill and therefore unmarked, then marked again by the second -
      // and still readable in between, which is the whole of what the second resync changed.
      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
      assert.equal(
        LocalDatabase.getRow(TASK, "t1").title,
        "from the first refill",
      );

      eventSource.listeners.synced({data: syncedFrame()});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });

    // The batch goes on naming the row whatever the refill said, because an unanswered write is
    // still this client's own work - what it has nothing left to fold over is a different matter.
    it("sweeps a row a pending update names when the refill did not deliver it", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "before the resync"});

      pending({
        data: {title: "mine"},
        id: "t1",
        op: "update",
        stamp: 1,
        type: TASK,
      });

      eventSource.listeners.sync_resync({data: resyncFrame()});
      eventSource.listeners.synced({data: syncedFrame()});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      assert.isTrue(Overlay.names(TASK, "t1"));
    });
  });

  describe("buildGreeting()", () => {
    const pageModule = Type.atom("Elixir.MyApp.BoardPage");

    // Both sides, so a test asserting that NO identity is presented states its own premise
    // rather than inheriting whatever the previous test or the previous suite adopted.
    beforeEach(() => {
      Replica.reset();
    });

    afterEach(() => {
      Replica.reset();
      delete globalThis.Hologram.sync;
    });

    it("tells the server what the bundle speaks, what it was built against, and where it is", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      assert.deepStrictEqual(SyncStream.buildGreeting(pageModule), {
        model_hash: "a3f9c2",
        page: "MyApp.BoardPage",
        protocol_version: 1,
      });
    });

    // One sync session per browser: the tab that leads is served sync and hands what it receives
    // to the rest, so a follower greets the way a bundle with no sync at all does.
    it("says nothing for a tab that does not lead its group", () => {
      // The bundle DOES carry sync here, or this would answer nothing for a reason that has
      // nothing to do with which tab leads.
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      Tabs.leader = false;

      try {
        assert.deepStrictEqual(SyncStream.buildGreeting(pageModule), {});
      } finally {
        Tabs.leader = true;
      }
    });

    it("says nothing for a bundle built before any of this existed", () => {
      assert.deepStrictEqual(SyncStream.buildGreeting(pageModule), {});
    });

    it("says nothing before the page has mounted", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      assert.deepStrictEqual(SyncStream.buildGreeting(null), {});
    });

    // A client coming back names where it got to, and is told what moved since instead of
    // everything it may see.
    it("names the place the client has been brought up to", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      SyncStream.syncCursor = "Nzc4LjA";

      assert.deepStrictEqual(SyncStream.buildGreeting(pageModule), {
        cursor: "Nzc4LjA",
        model_hash: "a3f9c2",
        page: "MyApp.BoardPage",
        protocol_version: 1,
      });
    });

    it("names no place for a client arriving with nothing", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      assert.notProperty(SyncStream.buildGreeting(pageModule), "cursor");
    });

    // The pair the browser is presenting, unchanged - what earns this client frames that say how
    // far its own writes are in.
    it("presents the replica identity the browser holds", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      Replica.adopt({id: "r1", token: "SFMyNTY.stated"});

      const greeting = SyncStream.buildGreeting(pageModule);

      assert.equal(greeting.replica_id, "r1");
      assert.equal(greeting.replica_token, "SFMyNTY.stated");
    });

    // An id is only worth the statement beside it, so half a pair is presented as none - the
    // server reads an id with no statement as no identity at all.
    it("presents neither half when the browser holds no identity", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      const greeting = SyncStream.buildGreeting(pageModule);

      assert.notProperty(greeting, "replica_id");
      assert.notProperty(greeting, "replica_token");
    });

    it("presents neither half for an id with no statement beside it", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      Replica.adopt({id: "r1", token: null});

      const greeting = SyncStream.buildGreeting(pageModule);

      assert.notProperty(greeting, "replica_id");
      assert.notProperty(greeting, "replica_token");
    });
  });

  // What a frame does to memory, driven directly rather than through a stream: the same call a
  // tab handed a frame by another tab will make.
  describe("receiveFrame()", () => {
    it("applies a deltas frame to memory and answers what it wrote", () => {
      const written = new Set(["MyApp.Task t1"]);

      const applying = sinon.stub(Deltas, "apply").returns(written);
      const landing = sinon.stub(Batches, "land");

      const answered = SyncStream.receiveFrame("sync_deltas", {
        applied_seq: 7,
        cursor: "Nzc4LjA",
        deltas: {put_entity: {}},
      });

      sinon.assert.calledOnceWithExactly(applying, {put_entity: {}});
      sinon.assert.calledOnceWithExactly(landing, 7, written);

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
      assert.equal(animationFrames.length, 1);
      assert.strictEqual(answered, written);
    });

    it("keeps the cursor a mid-fill deltas frame does not name", () => {
      sinon.stub(Deltas, "apply").returns(new Set());

      SyncStream.syncCursor = "Nzc4LjA";

      SyncStream.receiveFrame("sync_deltas", {
        applied_seq: null,
        cursor: null,
        deltas: {},
      });

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
    });

    it("marks the scope a synced marker names and takes its place", () => {
      SyncStream.receiveFrame("synced", {cursor: "Nzc4LjA", scope: "all"});

      assert.isTrue(LocalDatabase.isSynced("all"));
      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
      assert.equal(animationFrames.length, 1);
    });

    // A follower reaches this through the group rather than through a stream, and the page-load
    // half of a change of identity is posted to it exactly this way.
    it("starts over on a resync naming a change of identity", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});

      SyncStream.receiveFrame("sync_resync", {reason: "identity"});

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    // Nothing is repainted here on purpose - the refill's own frames schedule that.
    it("keeps what it holds on a resync, awaiting the refill", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});

      SyncStream.syncCursor = "Nzc4LjA";

      SyncStream.receiveFrame("sync_resync", {reason: "cursor"});

      assert.deepStrictEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "held",
      });

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
      ]);

      assert.isNull(SyncStream.syncCursor);
      assert.equal(animationFrames.length, 0);
    });
  });

  describe("sync_deltas event", () => {
    const TASK = "MyApp.Task";

    const frame = (overrides = {}) =>
      JSON.stringify(
        Object.assign(
          {
            applied_seq: null,
            cursor: "Nzc4LjA",
            deltas: {put_entity: {[TASK]: [{id: "t1", title: "Draft copy"}]}},
            model_hash: "a3f9c2",
            protocol_version: 1,
          },
          overrides,
        ),
      );

    // A batch of this client's own, sealed and waiting, naming the row the frames below carry.
    const pendingWrite = (id) => {
      Batches.open("tasks");

      Batches.current().append({
        data: {title: "mine"},
        id,
        op: "update",
        stamp: 1,
        type: TASK,
      });

      return Batches.close();
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
        modelHash: "a3f9c2",
        protocolVersion: 1,
      };
    });

    afterEach(() => {
      Batches.reset();
      delete globalThis.Hologram.sync;
    });

    it("files the rows the frame carries into the database", () => {
      eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Draft copy");
    });

    // What goes down is what LocalDatabase would hand back for the rows this frame wrote - built
    // there rather than here, so there is one spelling of a record in the system.
    it("writes the rows the frame wrote, with the place they are dated at", () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      eventSource.listeners.sync_deltas({data: frame()});

      assert.isTrue(persisting.calledOnce);

      assert.deepStrictEqual(
        persisting.firstCall.args[0],
        LocalDatabase.records([`${TASK} t1`]),
      );

      assert.equal(persisting.firstCall.args[1], "Nzc4LjA");
    });

    // Mid-fill frames name no place, and the adapter leaves the stored one standing rather than
    // clearing it - so the null is passed on rather than filtered out here.
    it("passes a frame naming no place straight through", () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      eventSource.listeners.sync_deltas({data: frame({cursor: null})});

      assert.isNull(persisting.firstCall.args[1]);
    });

    it("keeps the place the frame leaves the client at", () => {
      eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
    });

    // Mid-fill the server hands over no place, because a client holding part of a pot could not
    // honour the claim one makes - and a client that forgot the place it DID have would come
    // back asking only for what changed since a moment it never reached.
    it("keeps the place it already had when a frame names none", () => {
      eventSource.listeners.sync_deltas({data: frame()});
      eventSource.listeners.sync_deltas({data: frame({cursor: null})});

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
    });

    // The frame says how far this client's own batches are applied in what it carries, and the
    // writes of those batches stop being folded on top - which for a moved counter is the whole
    // difference between the number the server holds and one more than it.
    it("lands the writes of the batches the frame names", () => {
      const batch = pendingWrite("t1");

      eventSource.listeners.sync_deltas({data: frame({applied_seq: 1})});

      assert.isTrue(batch.isLanded(0));
    });

    it("lands nothing for a frame naming no number", () => {
      const batch = pendingWrite("t1");

      eventSource.listeners.sync_deltas({data: frame()});

      assert.isFalse(batch.isLanded(0));
    });

    // The frame carries a row this batch never wrote, so nothing of it is in what arrived.
    it("lands nothing on a batch whose rows the frame does not carry", () => {
      const batch = pendingWrite("t9");

      eventSource.listeners.sync_deltas({data: frame({applied_seq: 1})});

      assert.isFalse(batch.isLanded(0));
    });

    it("schedules a repaint rather than repainting in the handler", () => {
      const renderStub = sinon.stub(Hologram, "render");

      eventSource.listeners.sync_deltas({data: frame()});

      sinon.assert.notCalled(renderStub);
      assert.equal(animationFrames.length, 1);

      animationFrames[0]();

      sinon.assert.calledOnce(renderStub);
    });

    // A fill arrives as a burst of frames, and a repaint per frame would be work nobody sees.
    it("schedules one repaint however many frames arrive before it runs", () => {
      eventSource.listeners.sync_deltas({data: frame()});
      eventSource.listeners.sync_deltas({data: frame()});
      eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(animationFrames.length, 1);
    });

    // Between the destination's markup going up and its mount, the page on screen is one the
    // registry cannot answer for - the window an action is held in rather than run. Rendering
    // there would draw the page being left over the destination's virtual document.
    it("stands down from a repaint that lands mid-navigation", () => {
      const renderStub = sinon.stub(Hologram, "render");

      eventSource.listeners.sync_deltas({data: frame()});

      Hologram.domEpoch = Hologram.registryEpoch + 1;

      animationFrames[0]();

      sinon.assert.notCalled(renderStub);
    });

    it("schedules the next repaint once the scheduled one has run", () => {
      sinon.stub(Hologram, "render");

      eventSource.listeners.sync_deltas({data: frame()});
      animationFrames[0]();

      eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(animationFrames.length, 2);
    });
  });

  describe("sync_reload event", () => {
    const envelope = (reason) =>
      JSON.stringify({protocol_version: 1, reason: reason});

    afterEach(() => {
      GlobalRegistry.set("syncStaleReason", null);
    });

    it("records why the bundle is behind the server", () => {
      eventSource.listeners.sync_reload({data: envelope("model_hash")});

      assert.equal(GlobalRegistry.get("syncStaleReason"), "model_hash");
    });

    // Restarting the page would throw away what the person was doing to fix a mismatch they did
    // not cause - and a server serving an older client through lens chains is where this goes,
    // so a bundle behind the server is a thing to adapt to rather than to correct here.
    it("leaves the page where it is", () => {
      eventSource.listeners.sync_reload({data: envelope("model_hash")});

      sinon.assert.notCalled(globalThis.window.location.reload);
    });

    it("keeps what the client already holds", () => {
      LocalDatabase.putRow("MyApp.Task", {
        id: "t1",
        title: "rendered by the server",
      });

      eventSource.listeners.sync_reload({
        data: envelope("protocol_version"),
      });

      assert.equal(
        LocalDatabase.getRow("MyApp.Task", "t1").title,
        "rendered by the server",
      );
    });
  });

  describe("sync_resync event", () => {
    const TASK = "MyApp.Task";

    const envelope = (reason = "retention") =>
      JSON.stringify({protocol_version: 1, reason: reason});

    beforeEach(() => {
      // The refill's own frames are ingested here rather than stubbed, so the model the ingest
      // reads has to be the one a page would have been built with.
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
        modelHash: "a3f9c2",
        protocolVersion: 1,
      };

      LocalDatabase.putRow(TASK, {id: "t1", title: "held before the resync"});
      LocalDatabase.markSynced("all");
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;
    });

    // The rows stay on the screen and stay usable while the refill lands - an action reading or
    // writing one of them finds it there, where an emptied database answers that it holds no such
    // row and refuses the write.
    it("keeps what the client holds, awaiting the refill's word", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "held before the resync",
      });
    });

    it("marks every held row as awaiting the fill", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    // The one resync that replaces WHO is asking rather than what the server said. Those rows
    // were the previous person's, and this one may not see them - so they go now rather than at
    // the end of a fill, before anything can read them.
    it("drops what it holds when who is asking changed", () => {
      eventSource.listeners.sync_resync({data: envelope("identity")});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a row the refill delivered, as the server now spells it", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      eventSource.listeners.sync_deltas({
        data: JSON.stringify({
          applied_seq: null,
          cursor: null,
          deltas: {
            put_entity: {[TASK]: [{id: "t1", title: "as it now stands"}]},
          },
          model_hash: "a3f9c2",
          protocol_version: 1,
        }),
      });

      eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "as it now stands",
        title_sort: "as it now stands",
      });
    });

    it("takes a row the refill never delivered off at the marker", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });

    it("drops the stored rows and the place that dated them", () => {
      const clearing = sinon.stub(Durability, "clear");

      eventSource.listeners.sync_resync({data: envelope()});

      assert.isTrue(clearing.calledOnce);
    });

    it("drops the completeness it had, since the refill has not finished", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      assert.isFalse(LocalDatabase.isSynced("all"));
    });

    // The place described the rows, so it goes with them - a client cut off before the refill
    // lands would otherwise ask for what moved since a place it holds nothing from, and be given
    // deltas where it needs everything. What a client with no place greets with is pinned by
    // SyncStream.buildGreeting()'s own case.
    it("drops the place it had been brought up to", () => {
      SyncStream.syncCursor = "Nzc4LjA";

      eventSource.listeners.sync_resync({data: envelope()});

      assert.isNull(SyncStream.syncCursor);
    });

    // Repainting here would draw the rows exactly as they already are - the refill has changed
    // nothing yet - so the frames that do change something schedule the repaints.
    it("schedules no repaint of the gap it opens", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      assert.equal(animationFrames.length, 0);
    });

    // Even when the refill delivers nothing - a client that may now see none of what it held -
    // the marker ending it repaints, which is what takes those rows off the screen.
    it("leaves the marker ending the refill to repaint", () => {
      eventSource.listeners.sync_resync({data: envelope()});

      eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.equal(animationFrames.length, 1);
    });
  });

  describe("synced event", () => {
    const envelope = (scope, cursor = null) =>
      JSON.stringify({cursor: cursor, protocol_version: 1, scope: scope});

    it("records the scope the client may now answer for itself", () => {
      eventSource.listeners.synced({data: envelope("page")});

      assert.isTrue(LocalDatabase.isSynced("page"));
      assert.isFalse(LocalDatabase.isSynced("all"));
    });

    // What a query answers can change the moment a scope is complete - a count that was reading
    // the server's number starts counting rows.
    it("schedules a repaint", () => {
      eventSource.listeners.synced({data: envelope("all")});

      assert.equal(animationFrames.length, 1);
    });

    // For a client filled and then left alone this is the only frame that ever names a place, so
    // it is the only thing standing between it and being filled from nothing on its next visit.
    it("keeps the place the completeness marker names", () => {
      eventSource.listeners.synced({data: envelope("all", "Nzc4LjA")});

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
    });

    it("writes the place the completeness marker names", () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      eventSource.listeners.synced({data: envelope("all", "Nzc4LjA")});

      assert.isTrue(persisting.calledOnce);
      assert.deepStrictEqual(persisting.firstCall.args, [[], "Nzc4LjA"]);
    });

    // The page scope is narrower than the claim a place makes, so its marker names none - and a
    // server built before this frame carried one names nothing at all.
    it("leaves the place alone for a marker naming none", () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      eventSource.listeners.sync_deltas({
        data: JSON.stringify({
          applied_seq: null,
          cursor: "Nzc4LjA",
          deltas: {},
        }),
      });

      eventSource.listeners.synced({data: envelope("page")});

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");
      assert.isTrue(persisting.calledOnce);
    });
  });

  // The tabs of a browser that have no stream of their own are handed what this one receives.
  describe("telling the group", () => {
    const frame = () =>
      JSON.stringify({
        applied_seq: null,
        cursor: "Nzc4LjA",
        deltas: {},
        model_hash: "a3f9c2",
        protocol_version: 1,
      });

    it("hands each frame to the group, naming the page the stream was greeted with", () => {
      const posting = sinon.stub(Tabs, "post");

      GlobalRegistry.set("connectPageModule", "MyApp.TodosPage");

      eventSource.listeners.sync_deltas({data: frame()});

      assert.isTrue(posting.calledOnce);

      assert.deepStrictEqual(posting.firstCall.args[0], {
        event: "sync_deltas",
        frame: JSON.parse(frame()),
        kind: "frame",
        page: "MyApp.TodosPage",
      });
    });

    // The order is the whole reason a tab joining the group cannot miss a frame: the write
    // transaction is created before the message goes out, and IndexedDB orders what follows behind
    // it - so a tab that reads the store on hearing this reads a store that already holds it.
    it("writes the frame down before telling anyone about it", () => {
      const persisting = sinon.stub(Durability, "persistFrame");
      const posting = sinon.stub(Tabs, "post");

      eventSource.listeners.sync_deltas({data: frame()});

      assert.isTrue(persisting.calledBefore(posting));
    });

    it("hands over a completeness marker, a resync and a stale-bundle notice too", () => {
      const posting = sinon.stub(Tabs, "post");

      eventSource.listeners.synced({
        data: JSON.stringify({cursor: null, protocol_version: 1, scope: "all"}),
      });

      eventSource.listeners.sync_resync({
        data: JSON.stringify({
          protocol_version: 1,
          reason: "cursor_unreadable",
        }),
      });

      eventSource.listeners.sync_reload({
        data: JSON.stringify({protocol_version: 1, reason: "model_hash"}),
      });

      assert.deepStrictEqual(
        posting.args.map(([message]) => message.event),
        ["synced", "sync_resync", "sync_reload"],
      );
    });
  });
});

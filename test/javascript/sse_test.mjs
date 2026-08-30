"use strict";

import {
  assert,
  defineRuntimeGlobals,
  initComponentRegistryEntry,
  registerWebApis,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Batches from "../../assets/js/batches.mjs";
import Durability from "../../assets/js/durability.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Model from "../../assets/js/model.mjs";
import Replica from "../../assets/js/replica.mjs";
import Sse from "../../assets/js/sse.mjs";
import SubscriptionReceiptRegistry from "../../assets/js/subscription_receipt_registry.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// Without this the file passes only when something else in the run has installed sessionStorage
// first: every handler here that logs - a resync, a reload notice, a stream dying inside the
// stability window - writes there through Logger, and a suite that leans on its neighbours cannot
// be run by itself or trusted to say which change broke it.
registerWebApis();

describe("Sse", () => {
  let animationFrames;
  let fetchStub;
  let mockEventSource;
  let originalInstanceId;
  let originalWindow;

  const binding = (channel, cid) => Type.tuple([channel, Type.bitstring(cid)]);

  const receipt = (channel, cid, token) =>
    Type.tuple([channel, Type.bitstring(cid), Type.bitstring(token)]);

  const bindingA = binding(Type.atom("room_a"), "page");
  const bindingB = binding(Type.atom("room_b"), "widget");

  const encodedBindingA = Type.encodeMapKey(bindingA);
  const encodedBindingB = Type.encodeMapKey(bindingB);

  const receiptA = receipt(Type.atom("room_a"), "page", "token-a");
  const receiptB = receipt(Type.atom("room_b"), "widget", "token-b");

  function stubHandshakeResponse({
    handshakeId = "test-handshake-id",
    refreshedReceipts = Type.list(),
    ok = true,
    status = 200,
  } = {}) {
    fetchStub.resolves({
      ok,
      status,
      json: async () => ({
        handshakeId,
        refreshedReceipts: "encoded-refreshed-receipts",
      }),
    });

    return sinon
      .stub(Interpreter, "evaluateJavaScriptExpression")
      .callsFake((expression) => {
        if (expression === "encoded-refreshed-receipts") {
          return refreshedReceipts;
        }

        return Type.atom("noop");
      });
  }

  beforeEach(() => {
    ComponentRegistry.clear();

    Sse.eventSource = null;
    Sse.reconnectAttempts = 0;

    SubscriptionReceiptRegistry.entries.clear();

    mockEventSource = {
      close: sinon.spy(),
      listeners: {},
      addEventListener: function (type, listener) {
        this.listeners[type] = listener;
      },
      onerror: null,
      onopen: null,
    };

    globalThis.EventSource = sinon.stub().returns(mockEventSource);
    fetchStub = sinon.stub(globalThis, "fetch");

    Sse.renderScheduled = false;
    Sse.syncCursor = null;

    // Level, which is what "not mid-navigation" is - the state a repaint is allowed to run in.
    // Reset here rather than by the one test that parts them, so a failing assertion cannot leave
    // every test after it looking mid-navigation.
    Hologram.domEpoch = 0;
    Hologram.registryEpoch = 0;

    LocalDatabase.reset();
    Model.reset();

    originalWindow = globalThis.window;

    // The scheduled repaint is captured rather than run: what a test asserts is that ONE was
    // asked for, and running it here would drag a whole render into a transport test.
    animationFrames = [];

    globalThis.window = {
      location: {reload: sinon.spy()},
      requestAnimationFrame: (callback) => animationFrames.push(callback),
    };

    originalInstanceId = App.instanceId;
    App.instanceId = "test-instance-id";
  });

  afterEach(() => {
    sinon.restore();

    delete globalThis.EventSource;
    globalThis.window = originalWindow;

    App.instanceId = originalInstanceId;

    ComponentRegistry.clear();
    SubscriptionReceiptRegistry.entries.clear();
  });

  describe("buildHandshakePayload()", () => {
    it("returns an empty receipts list when no receipts are stored", () => {
      const payload = Sse.buildHandshakePayload();

      const expected = Type.map([
        [Type.atom("instance_id"), Type.bitstring("test-instance-id")],
        [Type.atom("receipts"), Type.list()],
      ]);

      assert.deepStrictEqual(payload, expected);
    });

    it("extracts the token from each stored receipt", () => {
      SubscriptionReceiptRegistry.entries.set("key-a", receiptA);
      SubscriptionReceiptRegistry.entries.set("key-b", receiptB);

      const payload = Sse.buildHandshakePayload();

      const expected = Type.map([
        [Type.atom("instance_id"), Type.bitstring("test-instance-id")],
        [
          Type.atom("receipts"),
          Type.list([Type.bitstring("token-a"), Type.bitstring("token-b")]),
        ],
      ]);

      assert.deepStrictEqual(payload, expected);
    });
  });

  describe("buildSyncGreeting()", () => {
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

      assert.deepStrictEqual(Sse.buildSyncGreeting(pageModule), {
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
        assert.deepStrictEqual(Sse.buildSyncGreeting(pageModule), {});
      } finally {
        Tabs.leader = true;
      }
    });

    it("says nothing for a bundle built before any of this existed", () => {
      assert.deepStrictEqual(Sse.buildSyncGreeting(pageModule), {});
    });

    it("says nothing before the page has mounted", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      assert.deepStrictEqual(Sse.buildSyncGreeting(null), {});
    });

    // A client coming back names where it got to, and is told what moved since instead of
    // everything it may see.
    it("names the place the client has been brought up to", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      Sse.syncCursor = "Nzc4LjA";

      assert.deepStrictEqual(Sse.buildSyncGreeting(pageModule), {
        cursor: "Nzc4LjA",
        model_hash: "a3f9c2",
        page: "MyApp.BoardPage",
        protocol_version: 1,
      });
    });

    it("names no place for a client arriving with nothing", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      assert.notProperty(Sse.buildSyncGreeting(pageModule), "cursor");
    });

    // The pair the browser is presenting, unchanged - what earns this client frames that say how
    // far its own writes are in.
    it("presents the replica identity the browser holds", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      Replica.adopt({id: "r1", token: "SFMyNTY.stated"});

      const greeting = Sse.buildSyncGreeting(pageModule);

      assert.equal(greeting.replica_id, "r1");
      assert.equal(greeting.replica_token, "SFMyNTY.stated");
    });

    // An id is only worth the statement beside it, so half a pair is presented as none - the
    // server reads an id with no statement as no identity at all.
    it("presents neither half when the browser holds no identity", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      const greeting = Sse.buildSyncGreeting(pageModule);

      assert.notProperty(greeting, "replica_id");
      assert.notProperty(greeting, "replica_token");
    });

    it("presents neither half for an id with no statement beside it", () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      Replica.adopt({id: "r1", token: null});

      const greeting = Sse.buildSyncGreeting(pageModule);

      assert.notProperty(greeting, "replica_id");
      assert.notProperty(greeting, "replica_token");
    });
  });

  describe("reconnect()", () => {
    // Both sides. The identity is module state, and the connect() tests below assert their whole
    // greeting URL - one left adopted here puts a replica on theirs and fails them, a long way
    // from anything that mentions an identity.
    beforeEach(() => {
      Replica.reset();
    });

    // The greeting is removed here rather than at the end of the test that sets it, as this file's
    // connect() describe already learned: a failed assertion skips the line and leaves it standing
    // for every test after it.
    afterEach(() => {
      Replica.reset();

      delete globalThis.Hologram.sync;
    });

    // The greeting is built at connect time and nowhere else, so a client whose identity changed
    // has to open a stream again for the server to hear about it.
    it("closes the stream and opens a new one carrying the current identity", async () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};

      sinon
        .stub(Hologram, "currentPageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      sinon.stub(Logger, "debug");
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      Replica.adopt({id: "r-refused", token: "statement-refused"});

      await Sse.connect();

      Replica.adopt({id: "r-fresh", token: "statement-fresh"});

      await Sse.reconnect();

      assert.isTrue(mockEventSource.close.calledOnce);
      assert.equal(globalThis.EventSource.callCount, 2);

      assert.include(
        globalThis.EventSource.secondCall.args[0],
        "replica_id=r-fresh&replica_token=statement-fresh",
      );
    });

    // A dying stream schedules its own retry. Left running, it opens a SECOND stream on top of
    // this one a moment later, and both deliver every action and every frame.
    it("calls off a retry the dying stream had scheduled", async () => {
      const timers = sinon.useFakeTimers();

      try {
        stubHandshakeResponse({handshakeId: "abc-handshake-id"});
        sinon.stub(Logger, "debug");

        await Sse.connect();

        Sse.eventSource.onerror({type: "error"});

        await Sse.reconnect();

        const opened = globalThis.EventSource.callCount;

        await timers.runAllAsync();

        assert.equal(globalThis.EventSource.callCount, opened);
      } finally {
        timers.restore();
      }
    });

    // Two connects can be in flight at once, and the one that arrives second must not leave the
    // first's stream open with nothing referring to it.
    it("closes a stream another connect had already opened", async () => {
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});
      sinon.stub(Logger, "debug");

      await Sse.connect();
      await Sse.connect();

      assert.isTrue(mockEventSource.close.calledOnce);
      assert.equal(globalThis.EventSource.callCount, 2);
    });

    // A stream that is replaced on purpose has earned no delay, and counting it as a failure would
    // make the next real one back off further than it should.
    it("leaves the failure count alone", async () => {
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});
      sinon.stub(Logger, "debug");

      await Sse.connect();
      await Sse.reconnect();

      assert.equal(Sse.reconnectAttempts, 0);
    });

    it("opens a stream when there is none to close", async () => {
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});
      sinon.stub(Logger, "debug");

      await Sse.reconnect();

      assert.equal(globalThis.EventSource.callCount, 1);
    });
  });

  describe("computeReconnectDelay()", () => {
    beforeEach(() => {
      sinon.stub(Math, "random").returns(0.5);
    });

    it("returns BASE_RECONNECT_DELAY on the first attempt", () => {
      assert.strictEqual(
        Sse.computeReconnectDelay(1),
        Sse.BASE_RECONNECT_DELAY,
      );
    });

    it("doubles on each subsequent attempt", () => {
      assert.strictEqual(Sse.computeReconnectDelay(2), 500);
      assert.strictEqual(Sse.computeReconnectDelay(3), 1000);
      assert.strictEqual(Sse.computeReconnectDelay(4), 2000);
      assert.strictEqual(Sse.computeReconnectDelay(5), 4000);
    });

    it("caps at MAX_RECONNECT_DELAY", () => {
      assert.strictEqual(
        Sse.computeReconnectDelay(100),
        Sse.MAX_RECONNECT_DELAY,
      );
    });

    it("applies negative jitter when Math.random returns 0", () => {
      Math.random.returns(0);

      assert.strictEqual(
        Sse.computeReconnectDelay(1),
        Sse.BASE_RECONNECT_DELAY * (1 - Sse.RECONNECT_JITTER),
      );
    });

    it("applies positive jitter when Math.random returns 1", () => {
      Math.random.returns(1);

      assert.strictEqual(
        Sse.computeReconnectDelay(1),
        Sse.BASE_RECONNECT_DELAY * (1 + Sse.RECONNECT_JITTER),
      );
    });
  });

  describe("connect()", () => {
    let setTimeoutSpy;

    // Removed here rather than at the end of the test that sets it: a failed assertion would skip
    // that line and leave the greeting in place for every test after it, which reads as a second
    // failure somewhere unrelated.
    afterEach(() => {
      delete globalThis.Hologram.sync;
    });

    beforeEach(() => {
      sinon.stub(Math, "random").returns(0.5);

      // Logger.debug schedules its write via setTimeout; stub it out so the
      // setTimeoutSpy below only captures the reconnect timer.
      sinon.stub(Logger, "debug");
      setTimeoutSpy = sinon.stub(globalThis, "setTimeout");
    });

    it("POSTs the handshake payload to the handshake endpoint before opening the EventSource", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      sinon.assert.calledWithMatch(fetchStub, "/hologram/sse/handshake", {
        method: "POST",
      });
    });

    it("opens the EventSource with both instance_id and handshake_id", async () => {
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id",
      );
    });

    it("opens the EventSource with the sync greeting when the bundle carries one", async () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      sinon
        .stub(Hologram, "currentPageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id&model_hash=a3f9c2&page=MyApp.BoardPage&protocol_version=1",
      );
    });

    // The listeners are registered again on every new stream, so the place has to outlive the
    // one that delivered it - a reconnect is exactly when the client needs to say what it has.
    it("opens the EventSource naming the place a previous stream left it at", async () => {
      globalThis.Hologram.sync = {modelHash: "a3f9c2", protocolVersion: 1};
      sinon
        .stub(Hologram, "currentPageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({
        data: JSON.stringify({cursor: "Nzc4LjA", deltas: {}}),
      });

      await Sse.connect();

      sinon.assert.calledWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id&model_hash=a3f9c2&page=MyApp.BoardPage&protocol_version=1&cursor=Nzc4LjA",
      );
    });

    it("merges refreshed receipts into the subscription receipt registry before opening", async () => {
      const refreshedReceipts = Type.list([
        receipt(Type.atom("room_a"), "page", "fresh-token"),
      ]);

      stubHandshakeResponse({refreshedReceipts});

      await Sse.connect();

      assert.strictEqual(SubscriptionReceiptRegistry.entries.size, 1);
    });

    it("does not open an EventSource when the handshake POST returns a non-2xx", async () => {
      stubHandshakeResponse({ok: false, status: 401});

      await Sse.connect();

      sinon.assert.notCalled(globalThis.EventSource);
    });

    it("increments reconnectAttempts and schedules a reconnect when the handshake POST returns a non-2xx", async () => {
      stubHandshakeResponse({ok: false, status: 503});

      await Sse.connect();

      assert.strictEqual(Sse.reconnectAttempts, 1);

      sinon.assert.calledWith(
        setTimeoutSpy,
        sinon.match.func,
        Sse.BASE_RECONNECT_DELAY,
      );
    });

    it("does not open an EventSource when fetch throws", async () => {
      fetchStub.rejects(new Error("network down"));

      await Sse.connect();

      sinon.assert.notCalled(globalThis.EventSource);
    });

    it("increments reconnectAttempts and schedules a reconnect when fetch throws", async () => {
      fetchStub.rejects(new Error("network down"));

      await Sse.connect();

      assert.strictEqual(Sse.reconnectAttempts, 1);

      sinon.assert.calledWith(
        setTimeoutSpy,
        sinon.match.func,
        Sse.BASE_RECONNECT_DELAY,
      );
    });

    it("exposes the opened EventSource as Sse.eventSource", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      assert.strictEqual(Sse.eventSource, mockEventSource);
    });

    it("triggers a full reload when every stored receipt was rejected", async () => {
      SubscriptionReceiptRegistry.entries.set(
        "key-a",
        receipt(Type.atom("room_a"), "page", "stale-token"),
      );

      stubHandshakeResponse({refreshedReceipts: Type.list()});

      await Sse.connect();

      sinon.assert.calledOnce(globalThis.window.location.reload);
      sinon.assert.notCalled(globalThis.EventSource);
    });

    it("does not reload on the initial fresh load with no stored receipts", async () => {
      stubHandshakeResponse({refreshedReceipts: Type.list()});

      await Sse.connect();

      sinon.assert.notCalled(globalThis.window.location.reload);
      sinon.assert.calledOnce(globalThis.EventSource);
    });

    it("does not reload when at least one stored receipt was validated", async () => {
      SubscriptionReceiptRegistry.entries.set(
        "key-a",
        receipt(Type.atom("room_a"), "page", "stale-token"),
      );

      const refreshedReceipts = Type.list([
        receipt(Type.atom("room_a"), "page", "fresh-token"),
      ]);

      stubHandshakeResponse({refreshedReceipts});

      await Sse.connect();

      sinon.assert.notCalled(globalThis.window.location.reload);
      sinon.assert.calledOnce(globalThis.EventSource);
    });
  });

  // What a frame does to memory, driven directly rather than through a stream: the same call a
  // tab handed a frame by another tab will make.
  describe("receiveFrame()", () => {
    it("applies a deltas frame to memory and answers what it wrote", () => {
      const written = new Set(["MyApp.Task t1"]);

      const applying = sinon.stub(Deltas, "apply").returns(written);
      const landing = sinon.stub(Batches, "land");

      const answered = Sse.receiveFrame("sync_deltas", {
        applied_seq: 7,
        cursor: "Nzc4LjA",
        deltas: {put_entity: {}},
      });

      sinon.assert.calledOnceWithExactly(applying, {put_entity: {}});
      sinon.assert.calledOnceWithExactly(landing, 7, written);

      assert.equal(Sse.syncCursor, "Nzc4LjA");
      assert.equal(animationFrames.length, 1);
      assert.strictEqual(answered, written);
    });

    it("keeps the cursor a mid-fill deltas frame does not name", () => {
      sinon.stub(Deltas, "apply").returns(new Set());

      Sse.syncCursor = "Nzc4LjA";

      Sse.receiveFrame("sync_deltas", {
        applied_seq: null,
        cursor: null,
        deltas: {},
      });

      assert.equal(Sse.syncCursor, "Nzc4LjA");
    });

    it("marks the scope a synced marker names and takes its place", () => {
      Sse.receiveFrame("synced", {cursor: "Nzc4LjA", scope: "all"});

      assert.isTrue(LocalDatabase.isSynced("all"));
      assert.equal(Sse.syncCursor, "Nzc4LjA");
      assert.equal(animationFrames.length, 1);
    });

    // A follower reaches this through the group rather than through a stream, and the page-load
    // half of a change of identity is posted to it exactly this way.
    it("starts over on a resync naming a change of identity", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});

      Sse.receiveFrame("sync_resync", {reason: "identity"});

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    // Nothing is repainted here on purpose - the refill's own frames schedule that.
    it("keeps what it holds on a resync, awaiting the refill", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});

      Sse.syncCursor = "Nzc4LjA";

      Sse.receiveFrame("sync_resync", {reason: "cursor"});

      assert.deepStrictEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "held",
      });

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
      ]);

      assert.isNull(Sse.syncCursor);
      assert.equal(animationFrames.length, 0);
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

    it("hands each frame to the group, naming the page the stream was greeted with", async () => {
      const posting = sinon.stub(Tabs, "post");

      GlobalRegistry.set("connectPageModule", "MyApp.TodosPage");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

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
    it("writes the frame down before telling anyone about it", async () => {
      const persisting = sinon.stub(Durability, "persistFrame");
      const posting = sinon.stub(Tabs, "post");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.isTrue(persisting.calledBefore(posting));
    });

    it("hands over a completeness marker, a resync and a stale-bundle notice too", async () => {
      const posting = sinon.stub(Tabs, "post");

      stubHandshakeResponse();

      await Sse.connect();

      Sse.eventSource.listeners.synced({
        data: JSON.stringify({cursor: null, protocol_version: 1, scope: "all"}),
      });

      Sse.eventSource.listeners.sync_resync({
        data: JSON.stringify({
          protocol_version: 1,
          reason: "cursor_unreadable",
        }),
      });

      Sse.eventSource.listeners.sync_reload({
        data: JSON.stringify({protocol_version: 1, reason: "model_hash"}),
      });

      assert.deepStrictEqual(
        posting.args.map(([message]) => message.event),
        ["synced", "sync_resync", "sync_reload"],
      );
    });
  });

  describe("onerror", () => {
    let loggerDebugStub;
    let setTimeoutSpy;

    beforeEach(() => {
      sinon.stub(Math, "random").returns(0.5);

      // Logger.debug schedules its write via setTimeout; stub it out so the
      // setTimeoutSpy below only captures the reconnect timer.
      loggerDebugStub = sinon.stub(Logger, "debug");
      setTimeoutSpy = sinon.stub(globalThis, "setTimeout");
    });

    it("logs the error", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledWithExactly(loggerDebugStub, "SSE error: error");
    });

    it("closes the failed EventSource", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledOnce(mockEventSource.close);
    });

    it("flips the sseConnected? signal to false on the global registry", async () => {
      const globalRegistrySetSpy = sinon.spy(GlobalRegistry, "set");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledWith(globalRegistrySetSpy, "sseConnected?", false);
    });

    it("increments reconnectAttempts and schedules a delayed reconnect", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      setTimeoutSpy.resetHistory();

      Sse.eventSource.onerror({type: "error"});

      assert.strictEqual(Sse.reconnectAttempts, 1);

      sinon.assert.calledWith(
        setTimeoutSpy,
        sinon.match.func,
        Sse.BASE_RECONNECT_DELAY,
      );
    });

    it("backs off exponentially on consecutive failures", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      setTimeoutSpy.resetHistory();

      Sse.eventSource.onerror({type: "error"});
      Sse.eventSource.onerror({type: "error"});
      Sse.eventSource.onerror({type: "error"});

      assert.strictEqual(setTimeoutSpy.getCall(0).args[1], 250);
      assert.strictEqual(setTimeoutSpy.getCall(1).args[1], 500);
      assert.strictEqual(setTimeoutSpy.getCall(2).args[1], 1000);
    });

    it("preserves the stored subscription receipts on connection error", async () => {
      const refreshedReceipts = Type.list([
        receipt(Type.atom("room_a"), "page", "fresh-token-a"),
      ]);

      stubHandshakeResponse({refreshedReceipts});

      await Sse.connect();
      assert.strictEqual(SubscriptionReceiptRegistry.entries.size, 1);

      Sse.eventSource.onerror({type: "error"});

      assert.strictEqual(SubscriptionReceiptRegistry.entries.size, 1);
    });
  });

  // The server sends the 200 before the work that can kill the stream runs, so opening
  // proves nothing on its own. The failure count is cleared only once a stream has
  // lasted, which is what keeps an open-then-die cycle from retrying at the floor
  // forever.
  describe("stability window", () => {
    let clock;

    beforeEach(() => {
      clock = sinon.useFakeTimers();
    });

    // A batch whose send got no answer is still pending, and this is the one signal that means
    // the network is worth trying again.
    it("sends the pending batches again when the stream comes back", async () => {
      stubHandshakeResponse();

      const flushStub = sinon.stub(Batches, "flush");

      await Sse.connect();
      Sse.eventSource.onopen({});

      sinon.assert.calledOnce(flushStub);
    });

    it("keeps counting failures when a stream dies inside the window", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onopen({});
      Sse.eventSource.onerror({type: "error"});

      assert.strictEqual(Sse.reconnectAttempts, 1);

      await Sse.connect();
      Sse.eventSource.onopen({});
      Sse.eventSource.onerror({type: "error"});

      assert.strictEqual(Sse.reconnectAttempts, 2);
    });

    it("clears the failure count once a stream outlives the window", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      Sse.reconnectAttempts = 5;
      Sse.eventSource.onopen({});

      clock.tick(Sse.STABLE_CONNECTION_MS);

      assert.strictEqual(Sse.reconnectAttempts, 0);
    });

    it("leaves the failure count alone until the window has fully elapsed", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      Sse.reconnectAttempts = 5;
      Sse.eventSource.onopen({});

      clock.tick(Sse.STABLE_CONNECTION_MS - 1);

      assert.strictEqual(Sse.reconnectAttempts, 5);
    });

    it("cancels the pending clear when the stream dies first", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onopen({});
      Sse.eventSource.onerror({type: "error"});

      clock.tick(Sse.STABLE_CONNECTION_MS * 2);

      assert.strictEqual(Sse.reconnectAttempts, 1);
    });

    // The property the window's value is chosen for: a stream dying sooner than the
    // longest retry delay can never clear the count, so the delay climbs to the ceiling
    // and stays there.
    it("climbs to the reconnect ceiling under a persistent open-then-die cycle", async () => {
      sinon.stub(Math, "random").returns(0.5);
      stubHandshakeResponse();

      for (const _cycle of [1, 2, 3, 4, 5, 6, 7]) {
        await Sse.connect();
        Sse.eventSource.onopen({});
        Sse.eventSource.onerror({type: "error"});
      }

      assert.strictEqual(
        Sse.computeReconnectDelay(Sse.reconnectAttempts),
        Sse.MAX_RECONNECT_DELAY,
      );
    });
  });

  describe("onopen", () => {
    it("flips the sseConnected? signal to true on the global registry", async () => {
      const globalRegistrySetSpy = sinon.spy(GlobalRegistry, "set");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onopen({});

      sinon.assert.calledWith(globalRegistrySetSpy, "sseConnected?", true);
    });
  });

  describe("action event", () => {
    it("schedules the action when the target cid is mounted", async () => {
      const cid = Type.bitstring("c1");
      initComponentRegistryEntry(cid);

      const decodedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        target: cid,
      });

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-action-expression").returns(decodedAction);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.listeners.action({data: "encoded-action-expression"});

      sinon.assert.calledWith(evalStub, "encoded-action-expression");

      sinon.assert.calledOnceWithExactly(scheduleStub, decodedAction);
    });

    it("silently drops the action when the target cid is not mounted", async () => {
      const decodedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        target: Type.bitstring("c_unmounted"),
      });

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-action-expression").returns(decodedAction);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.listeners.action({data: "encoded-action-expression"});

      sinon.assert.notCalled(scheduleStub);
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

    it("files the rows the frame carries into the database", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Draft copy");
    });

    // What goes down is what LocalDatabase would hand back for the rows this frame wrote - built
    // there rather than here, so there is one spelling of a record in the system.
    it("writes the rows the frame wrote, with the place they are dated at", async () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.isTrue(persisting.calledOnce);

      assert.deepStrictEqual(
        persisting.firstCall.args[0],
        LocalDatabase.records([`${TASK} t1`]),
      );

      assert.equal(persisting.firstCall.args[1], "Nzc4LjA");
    });

    // Mid-fill frames name no place, and the adapter leaves the stored one standing rather than
    // clearing it - so the null is passed on rather than filtered out here.
    it("passes a frame naming no place straight through", async () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame({cursor: null})});

      assert.isNull(persisting.firstCall.args[1]);
    });

    it("keeps the place the frame leaves the client at", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(Sse.syncCursor, "Nzc4LjA");
    });

    // Mid-fill the server hands over no place, because a client holding part of a pot could not
    // honour the claim one makes - and a client that forgot the place it DID have would come
    // back asking only for what changed since a moment it never reached.
    it("keeps the place it already had when a frame names none", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});
      Sse.eventSource.listeners.sync_deltas({data: frame({cursor: null})});

      assert.equal(Sse.syncCursor, "Nzc4LjA");
    });

    // The frame says how far this client's own batches are applied in what it carries, and the
    // writes of those batches stop being folded on top - which for a moved counter is the whole
    // difference between the number the server holds and one more than it.
    it("lands the writes of the batches the frame names", async () => {
      const batch = pendingWrite("t1");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame({applied_seq: 1})});

      assert.isTrue(batch.isLanded(0));
    });

    it("lands nothing for a frame naming no number", async () => {
      const batch = pendingWrite("t1");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.isFalse(batch.isLanded(0));
    });

    // The frame carries a row this batch never wrote, so nothing of it is in what arrived.
    it("lands nothing on a batch whose rows the frame does not carry", async () => {
      const batch = pendingWrite("t9");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame({applied_seq: 1})});

      assert.isFalse(batch.isLanded(0));
    });

    it("schedules a repaint rather than repainting in the handler", async () => {
      const renderStub = sinon.stub(Hologram, "render");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      sinon.assert.notCalled(renderStub);
      assert.equal(animationFrames.length, 1);

      animationFrames[0]();

      sinon.assert.calledOnce(renderStub);
    });

    // A fill arrives as a burst of frames, and a repaint per frame would be work nobody sees.
    it("schedules one repaint however many frames arrive before it runs", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      Sse.eventSource.listeners.sync_deltas({data: frame()});
      Sse.eventSource.listeners.sync_deltas({data: frame()});
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(animationFrames.length, 1);
    });

    // Between the destination's markup going up and its mount, the page on screen is one the
    // registry cannot answer for - the window an action is held in rather than run. Rendering
    // there would draw the page being left over the destination's virtual document.
    it("stands down from a repaint that lands mid-navigation", async () => {
      const renderStub = sinon.stub(Hologram, "render");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({data: frame()});

      Hologram.domEpoch = Hologram.registryEpoch + 1;

      animationFrames[0]();

      sinon.assert.notCalled(renderStub);
    });

    it("schedules the next repaint once the scheduled one has run", async () => {
      sinon.stub(Hologram, "render");
      stubHandshakeResponse();

      await Sse.connect();

      Sse.eventSource.listeners.sync_deltas({data: frame()});
      animationFrames[0]();

      Sse.eventSource.listeners.sync_deltas({data: frame()});

      assert.equal(animationFrames.length, 2);
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
    it("keeps what the client holds, awaiting the refill's word", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "held before the resync",
      });
    });

    it("marks every held row as awaiting the fill", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    // The one resync that replaces WHO is asking rather than what the server said. Those rows
    // were the previous person's, and this one may not see them - so they go now rather than at
    // the end of a fill, before anything can read them.
    it("drops what it holds when who is asking changed", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope("identity")});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a row the refill delivered, as the server now spells it", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      Sse.eventSource.listeners.sync_deltas({
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

      Sse.eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "as it now stands",
        title_sort: "as it now stands",
      });
    });

    it("takes a row the refill never delivered off at the marker", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      Sse.eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });

    it("drops the stored rows and the place that dated them", async () => {
      const clearing = sinon.stub(Durability, "clear");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.isTrue(clearing.calledOnce);
    });

    it("drops the completeness it had, since the refill has not finished", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.isFalse(LocalDatabase.isSynced("all"));
    });

    // The place described the rows, so it goes with them - a client cut off before the refill
    // lands would otherwise ask for what moved since a place it holds nothing from, and be given
    // deltas where it needs everything. What a client with no place greets with is pinned by
    // buildSyncGreeting()'s own case.
    it("drops the place it had been brought up to", async () => {
      stubHandshakeResponse();
      Sse.syncCursor = "Nzc4LjA";

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.isNull(Sse.syncCursor);
    });

    // Repainting here would draw the rows exactly as they already are - the refill has changed
    // nothing yet - so the frames that do change something schedule the repaints.
    it("schedules no repaint of the gap it opens", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      assert.equal(animationFrames.length, 0);
    });

    // Even when the refill delivers nothing - a client that may now see none of what it held -
    // the marker ending it repaints, which is what takes those rows off the screen.
    it("leaves the marker ending the refill to repaint", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_resync({data: envelope()});

      Sse.eventSource.listeners.synced({
        data: JSON.stringify({protocol_version: 1, scope: "all"}),
      });

      assert.equal(animationFrames.length, 1);
    });
  });

  describe("sync_reload event", () => {
    const envelope = (reason) =>
      JSON.stringify({protocol_version: 1, reason: reason});

    afterEach(() => {
      GlobalRegistry.set("syncStaleReason", null);
    });

    it("records why the bundle is behind the server", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_reload({data: envelope("model_hash")});

      assert.equal(GlobalRegistry.get("syncStaleReason"), "model_hash");
    });

    // Restarting the page would throw away what the person was doing to fix a mismatch they did
    // not cause - and a server serving an older client through lens chains is where this goes,
    // so a bundle behind the server is a thing to adapt to rather than to correct here.
    it("leaves the page where it is", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_reload({data: envelope("model_hash")});

      sinon.assert.notCalled(globalThis.window.location.reload);
    });

    it("keeps what the client already holds", async () => {
      LocalDatabase.putRow("MyApp.Task", {
        id: "t1",
        title: "rendered by the server",
      });

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_reload({
        data: envelope("protocol_version"),
      });

      assert.equal(
        LocalDatabase.getRow("MyApp.Task", "t1").title,
        "rendered by the server",
      );
    });
  });

  describe("synced event", () => {
    const envelope = (scope, cursor = null) =>
      JSON.stringify({cursor: cursor, protocol_version: 1, scope: scope});

    it("records the scope the client may now answer for itself", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.synced({data: envelope("page")});

      assert.isTrue(LocalDatabase.isSynced("page"));
      assert.isFalse(LocalDatabase.isSynced("all"));
    });

    // What a query answers can change the moment a scope is complete - a count that was reading
    // the server's number starts counting rows.
    it("schedules a repaint", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.synced({data: envelope("all")});

      assert.equal(animationFrames.length, 1);
    });

    // For a client filled and then left alone this is the only frame that ever names a place, so
    // it is the only thing standing between it and being filled from nothing on its next visit.
    it("keeps the place the completeness marker names", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.synced({data: envelope("all", "Nzc4LjA")});

      assert.equal(Sse.syncCursor, "Nzc4LjA");
    });

    it("writes the place the completeness marker names", async () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.synced({data: envelope("all", "Nzc4LjA")});

      assert.isTrue(persisting.calledOnce);
      assert.deepStrictEqual(persisting.firstCall.args, [[], "Nzc4LjA"]);
    });

    // The page scope is narrower than the claim a place makes, so its marker names none - and a
    // server built before this frame carried one names nothing at all.
    it("leaves the place alone for a marker naming none", async () => {
      const persisting = sinon.stub(Durability, "persistFrame");

      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({
        data: JSON.stringify({
          applied_seq: null,
          cursor: "Nzc4LjA",
          deltas: {},
        }),
      });

      Sse.eventSource.listeners.synced({data: envelope("page")});

      assert.equal(Sse.syncCursor, "Nzc4LjA");
      assert.isTrue(persisting.calledOnce);
    });
  });

  describe("broadcast event", () => {
    it("schedules an action for each mounted cid in the envelope", async () => {
      const chat = Type.bitstring("chat");
      const sidebar = Type.bitstring("sidebar");

      initComponentRegistryEntry(chat);
      initComponentRegistryEntry(sidebar);

      const actionName = Type.atom("my_action");
      const params = Type.map([[Type.atom("text"), Type.bitstring("hi")]]);
      const envelope = Type.tuple([
        actionName,
        params,
        Type.list([chat, sidebar]),
      ]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-broadcast").returns(envelope);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.listeners.broadcast({data: "encoded-broadcast"});

      sinon.assert.calledTwice(scheduleStub);

      sinon.assert.calledWith(
        scheduleStub,
        Type.actionStruct({name: actionName, params: params, target: chat}),
      );

      sinon.assert.calledWith(
        scheduleStub,
        Type.actionStruct({name: actionName, params: params, target: sidebar}),
      );
    });

    it("silently drops cids that are not mounted", async () => {
      const chat = Type.bitstring("chat");
      initComponentRegistryEntry(chat);

      const actionName = Type.atom("my_action");
      const params = Type.map();

      const envelope = Type.tuple([
        actionName,
        params,
        Type.list([chat, Type.bitstring("unmounted")]),
      ]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-broadcast").returns(envelope);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.listeners.broadcast({data: "encoded-broadcast"});

      sinon.assert.calledOnceWithExactly(
        scheduleStub,
        Type.actionStruct({name: actionName, params: params, target: chat}),
      );
    });

    it("is a no-op when the cids list is empty", async () => {
      const envelope = Type.tuple([
        Type.atom("my_action"),
        Type.map([]),
        Type.list([]),
      ]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-broadcast").returns(envelope);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.listeners.broadcast({data: "encoded-broadcast"});

      sinon.assert.notCalled(scheduleStub);
    });
  });

  describe("add_sub_receipts event", () => {
    it("inserts new entries and leaves non-matching entries intact", async () => {
      const adds = Type.list([receiptA]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-adds").returns(adds);

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      Sse.eventSource.listeners.add_sub_receipts({data: "encoded-adds"});

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        receiptA,
      );

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingB),
        receiptB,
      );
    });

    it("replaces an existing entry when an add carries the same binding", async () => {
      const oldReceiptA = receipt(Type.atom("room_a"), "page", "old-token-a");
      const newReceiptA = receipt(Type.atom("room_a"), "page", "new-token-a");
      const adds = Type.list([newReceiptA]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-adds").returns(adds);

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, oldReceiptA);

      Sse.eventSource.listeners.add_sub_receipts({data: "encoded-adds"});

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        newReceiptA,
      );
    });

    it("is a no-op when the receipts list is empty", async () => {
      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-adds").returns(Type.list());

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);

      Sse.eventSource.listeners.add_sub_receipts({data: "encoded-adds"});

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        receiptA,
      );
    });
  });

  describe("drop_sub_receipts event", () => {
    it("purges the named entries from the receipt registry", async () => {
      const dropBindings = Type.list([bindingA]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-drop-keys").returns(dropBindings);

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);
      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      Sse.eventSource.listeners.drop_sub_receipts({data: "encoded-drop-keys"});

      assert.isFalse(SubscriptionReceiptRegistry.entries.has(encodedBindingA));
      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedBindingB));
    });

    it("is a no-op when the keys list is empty", async () => {
      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-drop-keys").returns(Type.list());

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);

      Sse.eventSource.listeners.drop_sub_receipts({data: "encoded-drop-keys"});

      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedBindingA));
    });
  });

  describe("refresh_sub_receipts event", () => {
    const staleReceiptA = receipt(Type.atom("room_a"), "page", "stale-token-a");
    const freshReceiptA = receipt(Type.atom("room_a"), "page", "fresh-token-a");

    it("replaces matching entries with refreshed receipts and leaves non-matching entries intact", async () => {
      const refreshed = Type.list([freshReceiptA]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-refreshed").returns(refreshed);

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, staleReceiptA);
      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      Sse.eventSource.listeners.refresh_sub_receipts({
        data: "encoded-refreshed",
      });

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        freshReceiptA,
      );

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingB),
        receiptB,
      );
    });

    it("is a no-op when the receipts list is empty", async () => {
      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-refreshed").returns(Type.list());

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, staleReceiptA);

      Sse.eventSource.listeners.refresh_sub_receipts({
        data: "encoded-refreshed",
      });

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        staleReceiptA,
      );
    });
  });
});

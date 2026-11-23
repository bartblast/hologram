"use strict";

import {
  assert,
  defineRuntimeGlobals,
  initComponentRegistryEntry,
  registerWebApis,
  setDataLayer,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Batches from "../../assets/js/batches.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Config from "../../assets/js/config.mjs";
import Deserializer from "../../assets/js/deserializer.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Replica from "../../assets/js/replica.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Sse from "../../assets/js/sse.mjs";
import SubscriptionReceiptRegistry from "../../assets/js/subscription_receipt_registry.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
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

  // A term the way the server sends it: the serialized text for an event whose data is the term
  // alone, parsed along with its envelope for an action, a broadcast or the handshake reply.
  const serializedText = (term) => Serializer.serialize(term, "server");
  const serializedValue = (term) => JSON.parse(serializedText(term));

  function stubHandshakeResponse({
    handshakeId = "test-handshake-id",
    heartbeatIntervalMs = 15_000,
    refreshedReceipts = Type.list(),
    ok = true,
    replica = undefined,
    replicaRefused = undefined,
    status = 200,
  } = {}) {
    const serializedRefreshedReceipts = serializedValue(refreshedReceipts);

    fetchStub.resolves({
      ok,
      status,
      json: async () => ({
        handshakeId,
        heartbeatIntervalMs,
        refreshedReceipts: serializedRefreshedReceipts,
        replica,
        replicaRefused,
      }),
    });
  }

  beforeEach(() => {
    ComponentRegistry.clear();

    Sse.eventSource = null;
    Sse.heartbeatIntervalMs = null;
    Sse.heartbeatTimer = null;
    Sse.isStarted = false;
    Sse.isSuspended = false;
    Sse.reconnectAttempts = 0;
    Sse.reconnectTimer = null;
    Sse.reloadDeferrals = 0;
    Sse.isAskingForReplica = false;
    Sse.replicaAskId = 0;
    Sse.runId = 0;
    Sse.stabilityTimer = null;

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

    SyncStream.renderScheduled = false;
    SyncStream.syncCursor = null;

    LocalDatabase.reset();

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
    Hologram.dataLayer = null;

    App.instanceId = originalInstanceId;

    ComponentRegistry.clear();
    Replica.reset();
    SubscriptionReceiptRegistry.entries.clear();
  });

  describe("askForReplica()", () => {
    const minted = {id: "replica-minted", token: "token-minted"};

    let flush, timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers({toFake: ["setTimeout", "clearTimeout"]});
      flush = sinon.stub(Batches, "flush").resolves();

      sinon.stub(Math, "random").returns(0.5);
      sinon.stub(Logger, "debug");

      setDataLayer();

      sinon.stub(Hologram.dataLayer, "listenToStream");

      Replica.offer({id: "replica-page", token: "token-page"});
      Replica.requestMint();
      Replica.refuseMint();

      Sse.eventSource = mockEventSource;
    });

    const askToTheEnd = async () => {
      const asking = Sse.askForReplica();

      await timers.tickAsync(
        Sse.MAX_RECONNECT_DELAY * Sse.MAX_REPLICA_ASKS * 2,
      );
      await asking;
    };

    // The stream hears of a sign-in before the browser has the new session cookie.
    it("takes a pair that arrives after refusals under the old cookie", async () => {
      fetchStub.onCall(0).resolves({
        ok: true,
        json: async () => ({replicaRefused: true}),
      });

      fetchStub.resolves({
        ok: true,
        json: async () => ({
          handshakeId: "test-handshake-id",
          heartbeatIntervalMs: 15_000,
          refreshedReceipts: serializedValue(Type.list()),
          replica: minted,
        }),
      });

      await askToTheEnd();

      assert.equal(Replica.id, "replica-minted");
      assert.isFalse(Replica.mintRefused);
      sinon.assert.calledOnce(flush);
    });

    it("replaces the stream once a pair has arrived", async () => {
      stubHandshakeResponse({replica: minted});

      await askToTheEnd();

      sinon.assert.calledOnce(mockEventSource.close);
      sinon.assert.calledOnce(globalThis.EventSource);
    });

    // A stream reopened under the old cookie would serve the previous user's rows.
    it("leaves the open stream alone while refused", async () => {
      stubHandshakeResponse({replicaRefused: true});

      await askToTheEnd();

      sinon.assert.notCalled(mockEventSource.close);
      sinon.assert.notCalled(globalThis.EventSource);
      sinon.assert.callCount(fetchStub, Sse.MAX_REPLICA_ASKS);
      assert.isTrue(Replica.mintRefused);
    });

    it("keeps asking after a request that failed", async () => {
      fetchStub.onCall(0).rejects(new Error("offline"));

      fetchStub.resolves({
        ok: true,
        json: async () => ({
          handshakeId: "test-handshake-id",
          heartbeatIntervalMs: 15_000,
          refreshedReceipts: serializedValue(Type.list()),
          replica: minted,
        }),
      });

      await askToTheEnd();

      assert.equal(Replica.id, "replica-minted");
    });

    it("moves on from a request that never answers", async () => {
      fetchStub.onCall(0).callsFake(
        (_path, {signal}) =>
          new Promise((_resolve, reject) => {
            signal?.addEventListener("abort", () =>
              reject(new Error("aborted")),
            );
          }),
      );

      fetchStub.resolves({
        ok: true,
        json: async () => ({
          handshakeId: "test-handshake-id",
          heartbeatIntervalMs: 15_000,
          refreshedReceipts: serializedValue(Type.list()),
          replica: minted,
        }),
      });

      Sse.askForReplica();

      await timers.tickAsync(
        Config.mutationTimeoutMs + Sse.MAX_RECONNECT_DELAY * 2,
      );

      assert.equal(Replica.id, "replica-minted");
    });

    it("stops once the page is left", async () => {
      stubHandshakeResponse({replica: minted});

      const asking = Sse.askForReplica();

      Sse.suspend();

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY);
      await asking;

      sinon.assert.notCalled(fetchStub);
      assert.isTrue(Replica.mintRefused);
    });

    it("starts over when the page comes back, with one ask running", async () => {
      stubHandshakeResponse({replicaRefused: true});

      const asking = Sse.askForReplica();

      Sse.suspend();
      Sse.resume();

      await timers.tickAsync(
        Sse.MAX_RECONNECT_DELAY * Sse.MAX_REPLICA_ASKS * 2,
      );
      await asking;

      sinon.assert.callCount(fetchStub, Sse.MAX_REPLICA_ASKS);
      assert.isFalse(Sse.isAskingForReplica);
    });

    // The new cookie can land after the one handshake the return makes.
    it("takes a pair that arrives after the page came back", async () => {
      stubHandshakeResponse({replicaRefused: true});

      Sse.askForReplica();
      Sse.suspend();
      Sse.resume();

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY);

      stubHandshakeResponse({replica: minted});

      await timers.tickAsync(
        Sse.MAX_RECONNECT_DELAY * Sse.MAX_REPLICA_ASKS * 2,
      );

      assert.equal(Replica.id, "replica-minted");
    });

    it("starts no ask on a return when none was running", async () => {
      Sse.suspend();
      Sse.resume();

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY * 2);

      sinon.assert.notCalled(fetchStub);
    });

    it("starts no ask on a return after the last one ended", async () => {
      stubHandshakeResponse({replicaRefused: true});

      await askToTheEnd();

      fetchStub.resetHistory();

      Sse.suspend();
      Sse.resume();

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY * 2);

      sinon.assert.notCalled(fetchStub);
    });

    it("drops an answer that arrives after the page was left", async () => {
      let answer;

      stubHandshakeResponse({replicaRefused: true});

      fetchStub.onFirstCall().returns(
        new Promise((resolve) => {
          answer = resolve;
        }),
      );

      Sse.askForReplica();

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY);

      Sse.suspend();
      Sse.resume();

      answer({ok: true, json: async () => ({replica: minted})});

      await timers.tickAsync(
        Sse.MAX_RECONNECT_DELAY * Sse.MAX_REPLICA_ASKS * 2,
      );

      assert.equal(Replica.id, "replica-page");
      assert.isTrue(Replica.mintRefused);
    });

    it("stops once another handshake has brought a pair", async () => {
      stubHandshakeResponse({replicaRefused: true});

      const asking = Sse.askForReplica();

      Replica.takeMinted(minted);

      await timers.tickAsync(Sse.MAX_RECONNECT_DELAY);
      await asking;

      sinon.assert.notCalled(fetchStub);
    });

    it("leaves only the latest asking running", async () => {
      stubHandshakeResponse({replicaRefused: true});

      const first = Sse.askForReplica();
      const second = Sse.askForReplica();

      await timers.tickAsync(
        Sse.MAX_RECONNECT_DELAY * Sse.MAX_REPLICA_ASKS * 2,
      );
      await Promise.all([first, second]);

      sinon.assert.callCount(fetchStub, Sse.MAX_REPLICA_ASKS);
    });
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

    it("asks for an identity while the tab is waiting for one", () => {
      setDataLayer();
      Replica.adopt({id: "replica-held", token: "token-held"});
      Replica.requestMint();

      const payload = Sse.buildHandshakePayload();

      const expected = Type.map([
        [Type.atom("instance_id"), Type.bitstring("test-instance-id")],
        [Type.atom("receipts"), Type.list()],
        [Type.atom("replica_id"), Type.bitstring("replica-held")],
        [Type.atom("replica_token"), Type.bitstring("token-held")],
      ]);

      assert.deepStrictEqual(payload, expected);
    });
  });

  describe("reconnect()", () => {
    // Answered late, it would close the stream the restart opened and open one of its own.
    it("drops a handshake already in flight", async () => {
      let answer;

      stubHandshakeResponse();

      fetchStub.onFirstCall().returns(
        new Promise((resolve) => {
          answer = resolve;
        }),
      );

      const overtaken = Sse.connect();

      await Sse.reconnect();

      sinon.assert.calledOnce(globalThis.EventSource);

      answer({
        json: async () => ({
          handshakeId: "overtaken",
          heartbeatIntervalMs: 15_000,
          refreshedReceipts: serializedValue(Type.list()),
        }),
        ok: true,
        status: 200,
      });

      await overtaken;

      sinon.assert.calledOnce(globalThis.EventSource);
      sinon.assert.notCalled(mockEventSource.close);
    });

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
      setDataLayer();
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };

      sinon
        .stub(Hologram, "pageModule")
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

    // A left page has no stream to replace, and one opened here would outlive the document.
    it("opens no stream on a page that has been left", async () => {
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      Sse.suspend();

      await Sse.reconnect();

      sinon.assert.notCalled(fetchStub);
      sinon.assert.notCalled(globalThis.EventSource);
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

    // Until the new stream opens there is none, and a page that says otherwise lets a test that
    // waits for the connection go on too early.
    //
    // On a fake clock: the opened stream sets the heartbeat watchdog and the stability timer, and a
    // failed assertion would leave them running into the tests after this one.
    it("says the page is not connected until the new stream opens", async () => {
      const timers = sinon.useFakeTimers();

      try {
        stubHandshakeResponse({handshakeId: "abc-handshake-id"});
        sinon.stub(Logger, "debug");

        await Sse.connect();
        Sse.eventSource.onopen({});

        assert.isTrue(GlobalRegistry.get("sseConnected?"));

        fetchStub.returns(new Promise(() => {}));

        const setting = sinon.spy(GlobalRegistry, "set");

        Sse.reconnect();

        sinon.assert.calledOnceWithExactly(setting, "sseConnected?", false);
      } finally {
        timers.restore();
      }
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

    describe("an identity the handshake brought", () => {
      const minted = {id: "replica-minted", token: "token-minted"};

      let flush, greetedWith;

      beforeEach(() => {
        greetedWith = null;
        flush = sinon.stub(Batches, "flush").resolves();

        setDataLayer();

        sinon.stub(Hologram.dataLayer, "buildStreamGreeting").callsFake(() => {
          greetedWith = Replica.id;

          return {};
        });

        sinon.stub(Hologram.dataLayer, "listenToStream");

        Replica.offer({id: "replica-page", token: "token-page"});
      });

      it("is taken before the stream is greeted", async () => {
        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        await Sse.connect();

        assert.equal(greetedWith, "replica-minted");
        assert.isFalse(Replica.awaitingMint);
      });

      // A proxy can block the stream while writes still get through, so it can't wait for onopen.
      it("wakes the sender before the stream has opened", async () => {
        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        await Sse.connect();

        sinon.assert.calledOnce(flush);
      });

      it("is passed over by a tab that is not waiting for one", async () => {
        stubHandshakeResponse({replica: minted});

        await Sse.connect();

        assert.equal(greetedWith, "replica-page");
        sinon.assert.notCalled(flush);
      });

      it("is not taken by a connect the page has left", async () => {
        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        const connecting = Sse.connect();

        Sse.suspend();
        await connecting;

        assert.equal(Replica.id, "replica-page");
        assert.isTrue(Replica.awaitingMint);
      });

      // The server won't mint for this tab's owner, and asking again would get the same answer.
      it("opens the stream and stops asking when the server refuses", async () => {
        Replica.requestMint();
        stubHandshakeResponse({replicaRefused: true});

        await Sse.connect();

        sinon.assert.calledOnce(globalThis.EventSource);
        assert.isFalse(Replica.awaitingMint);
        assert.isTrue(Replica.mintRefused);
        assert.equal(Replica.id, "replica-page");
        sinon.assert.notCalled(flush);
      });

      // The stored pair can be from a session that has ended, while the page's own is still good.
      it("asks again with the page's pair when the stored one is refused", async () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        Replica.adopt({id: "replica-stored", token: "token-stored"});
        Replica.requestMint();
        stubHandshakeResponse({replicaRefused: true});

        await Sse.connect();

        sinon.assert.notCalled(globalThis.EventSource);
        assert.equal(Replica.id, "replica-page");
        assert.isTrue(Replica.awaitingMint);

        stubHandshakeResponse({replica: minted});

        timers.tick(Sse.MAX_RECONNECT_DELAY * 2);
        await new Promise((resolve) => setImmediate(resolve));

        assert.equal(Replica.id, "replica-minted");
      });

      it("takes an identity a later handshake brings after a refusal", async () => {
        Replica.requestMint();
        stubHandshakeResponse({replicaRefused: true});

        await Sse.connect();

        const refusedPayload = Sse.buildHandshakePayload();

        assert.isTrue(Replica.mintRefused);
        assert.include(
          Serializer.serialize(refusedPayload, "server"),
          "areplica_id",
        );

        stubHandshakeResponse({replica: minted});

        await Sse.connect();

        assert.equal(Replica.id, "replica-minted");
        assert.isFalse(Replica.mintRefused);
        sinon.assert.calledOnce(flush);
      });

      it("asks again when the answer brought no identity", async () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        Replica.requestMint();
        stubHandshakeResponse();

        await Sse.connect();

        sinon.assert.notCalled(globalThis.EventSource);
        assert.isTrue(Replica.awaitingMint);

        stubHandshakeResponse({replica: minted});

        timers.tick(Sse.MAX_RECONNECT_DELAY * 2);
        await new Promise((resolve) => setImmediate(resolve));

        assert.equal(Replica.id, "replica-minted");
        sinon.assert.calledOnce(globalThis.EventSource);
      });

      // The server matches on these exact encoded values, so the client's spelling is pinned here.
      it("spells the request the way the server reads it", () => {
        Replica.requestMint();

        const serialized = Serializer.serialize(
          Sse.buildHandshakePayload(),
          "server",
        );

        assert.include(serialized, '"areplica_id"');
        assert.include(serialized, '"areplica_token"');
      });

      // Only this tab's memory holds a write waiting for the identity, so a reload ahead of the
      // send would lose it.
      it("lets the sender finish before a reload for expired receipts", async () => {
        let finishSending;

        flush.returns(
          new Promise((resolve) => {
            finishSending = resolve;
          }),
        );

        SubscriptionReceiptRegistry.entries.set("key-a", receiptA);
        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        const connecting = Sse.connect();

        await new Promise((resolve) => setImmediate(resolve));

        sinon.assert.calledOnce(flush);
        sinon.assert.notCalled(globalThis.window.location.reload);

        finishSending();
        await connecting;

        sinon.assert.calledOnce(globalThis.window.location.reload);
      });

      describe("a write still unsent when the receipts have expired", () => {
        let holdsUnsentWrites, timers;

        beforeEach(() => {
          timers = sinon.useFakeTimers({
            toFake: ["setTimeout", "clearTimeout"],
          });

          holdsUnsentWrites = sinon
            .stub(Hologram.dataLayer, "holdsUnsentWrites")
            .returns(true);

          SubscriptionReceiptRegistry.entries.set("key-a", receiptA);
          stubHandshakeResponse();
        });

        it("puts off the reload and tries the handshake again", async () => {
          await Sse.connect();

          sinon.assert.notCalled(globalThis.window.location.reload);
          sinon.assert.notCalled(globalThis.EventSource);

          timers.tick(Sse.MAX_RECONNECT_DELAY * 2);
          await new Promise((resolve) => setImmediate(resolve));

          sinon.assert.calledTwice(fetchStub);
        });

        it("reloads once the write has gone", async () => {
          await Sse.connect();

          holdsUnsentWrites.returns(false);

          await Sse.connect();

          sinon.assert.calledOnce(globalThis.window.location.reload);
        });

        it("gives up on a later handshake that never answers", async () => {
          const settle = () => new Promise((resolve) => setImmediate(resolve));

          await Sse.connect();

          holdsUnsentWrites.returns(false);

          fetchStub.onSecondCall().callsFake(
            (_path, {signal}) =>
              new Promise((_resolve, reject) => {
                signal.addEventListener("abort", () =>
                  reject(new DOMException("aborted", "AbortError")),
                );
              }),
          );

          timers.tick(Sse.MAX_RECONNECT_DELAY);
          await settle();

          sinon.assert.calledTwice(fetchStub);

          timers.tick(Config.mutationTimeoutMs);
          await settle();

          timers.tick(Sse.MAX_RECONNECT_DELAY);
          await settle();

          sinon.assert.calledThrice(fetchStub);
          sinon.assert.calledOnce(globalThis.window.location.reload);
        });

        it("sets a deadline on the first handshake that could put it off", () => {
          fetchStub.returns(new Promise(() => {}));

          Sse.connect();

          const {signal} = fetchStub.firstCall.args[1];

          timers.tick(Config.mutationTimeoutMs);

          assert.isTrue(signal.aborted);
        });

        // Leaving the page starts the count again, while the write is still here.
        it("sets a deadline on the handshake after the page comes back", async () => {
          await Sse.connect();

          Sse.isStarted = true;
          Sse.suspend();

          fetchStub.returns(new Promise(() => {}));

          Sse.resume();

          const {signal} = fetchStub.secondCall.args[1];

          timers.tick(Config.mutationTimeoutMs);

          assert.isTrue(signal.aborted);
        });

        // A write the server keeps refusing never leaves the queue.
        it("reloads anyway once the limit is reached", async () => {
          for (let i = 0; i < Sse.MAX_RELOAD_DEFERRALS; i++) {
            await Sse.connect();
          }

          sinon.assert.notCalled(globalThis.window.location.reload);

          await Sse.connect();

          sinon.assert.calledOnce(globalThis.window.location.reload);
        });

        it("starts the count again after a handshake with live receipts", async () => {
          await Sse.connect();

          stubHandshakeResponse({
            refreshedReceipts: Type.list([
              Type.tuple([
                Type.bitstring("key-a"),
                Type.integer(1),
                Type.bitstring("token-a"),
              ]),
            ]),
          });

          await Sse.connect();

          assert.equal(Sse.reloadDeferrals, 0);
        });

        // Leaving the page resets the backoff too, so a count kept across it would spend what's
        // left of the limit in moments and reload ahead of the sender's next try.
        it("starts the count again when the page is left", async () => {
          await Sse.connect();

          assert.equal(Sse.reloadDeferrals, 1);

          Sse.suspend();

          assert.equal(Sse.reloadDeferrals, 0);
        });

        it("still decides when the sender failed", async () => {
          flush.rejects(new Error("refused"));
          Replica.requestMint();
          stubHandshakeResponse({replica: minted});

          await Sse.connect();

          assert.equal(Sse.reloadDeferrals, 1);
        });
      });

      it("does not reload a page left while the sender was finishing", async () => {
        let finishSending;

        flush.returns(
          new Promise((resolve) => {
            finishSending = resolve;
          }),
        );

        SubscriptionReceiptRegistry.entries.set("key-a", receiptA);
        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        const connecting = Sse.connect();

        await new Promise((resolve) => setImmediate(resolve));

        Sse.suspend();
        finishSending();
        await connecting;

        sinon.assert.notCalled(globalThis.window.location.reload);
      });

      it("gives up on a handshake that never answers and asks again", async () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        fetchStub.onFirstCall().callsFake(
          (_path, {signal}) =>
            new Promise((_resolve, reject) => {
              signal.addEventListener("abort", () =>
                reject(new DOMException("aborted", "AbortError")),
              );
            }),
        );

        const connecting = Sse.connect();

        timers.tick(Config.mutationTimeoutMs);
        await connecting;

        assert.isTrue(Replica.awaitingMint);

        timers.tick(Sse.MAX_RECONNECT_DELAY * 2);
        await new Promise((resolve) => setImmediate(resolve));

        sinon.assert.calledTwice(fetchStub);
        assert.equal(Replica.id, "replica-minted");
      });

      it("keeps no deadline on a handshake once it has answered", async () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        Replica.requestMint();
        stubHandshakeResponse({replica: minted});

        await Sse.connect();

        const {signal} = fetchStub.firstCall.args[1];

        timers.tick(Config.mutationTimeoutMs);

        assert.isFalse(signal.aborted);
      });

      // Its writes wait for a handshake to bring an identity, and only a stream can tell it to ask.
      it("sets a deadline on the handshake of a refused tab", () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        Replica.requestMint();
        Replica.refuseMint();

        fetchStub.returns(new Promise(() => {}));

        Sse.connect();

        const {signal} = fetchStub.firstCall.args[1];

        timers.tick(Config.mutationTimeoutMs);

        assert.isTrue(signal.aborted);
      });

      it("sets no deadline on a handshake while no identity is wanted", async () => {
        const timers = sinon.useFakeTimers({
          toFake: ["setTimeout", "clearTimeout"],
        });

        fetchStub.returns(new Promise(() => {}));

        Sse.connect();

        const {signal} = fetchStub.firstCall.args[1];

        timers.tick(Config.mutationTimeoutMs);

        assert.isFalse(signal.aborted);
      });
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

    // An app without a data model has no data layer to greet for or to listen with: the stream
    // carries its realtime traffic and nothing else.
    it("greets with nothing and listens for no sync kind without a data layer", async () => {
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      try {
        await Sse.connect();
      } finally {
        delete globalThis.Hologram.sync;
      }

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id",
      );

      assert.notProperty(mockEventSource.listeners, "sync_deltas");
    });

    it("opens the EventSource with the sync greeting when the bundle carries one", async () => {
      setDataLayer();
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id&model_hash=a3f9c2&page=MyApp.BoardPage&protocol_version=1&policy_hash=0123456789abcdef",
      );
    });

    // A fill follows a greeting that names no place, with no resync frame in front of it - which
    // is where a client cut off part way through a fill comes back.
    it("marks every held row when it greets with no place", async () => {
      setDataLayer();
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
      ]);
    });

    it("leaves the rows alone when it greets with a place", async () => {
      setDataLayer();
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});
      SyncStream.syncCursor = "Nzc4LjA";
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    // A tab that does not lead greets with nothing about sync, so NO fill follows - and rows
    // marked here would be swept the moment the leading tab says the pot is complete, taking away
    // rows this browser holds rightly. The same goes for a page that has not mounted.
    it("leaves the rows alone for a tab greeting with no sync at all", async () => {
      setDataLayer();
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "held"});
      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      Tabs.leader = false;

      try {
        await Sse.connect();
      } finally {
        Tabs.leader = true;
      }

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    // The listeners are registered again on every new stream, so the place has to outlive the
    // one that delivered it - a reconnect is exactly when the client needs to say what it has.
    it("opens the EventSource naming the place a previous stream left it at", async () => {
      setDataLayer();
      globalThis.Hologram.sync = {
        model: {},
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.BoardPage"));

      stubHandshakeResponse({handshakeId: "abc-handshake-id"});

      await Sse.connect();
      Sse.eventSource.listeners.sync_deltas({
        data: JSON.stringify({cursor: "Nzc4LjA", deltas: {}}),
      });

      await Sse.connect();

      sinon.assert.calledWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id&handshake_id=abc-handshake-id&model_hash=a3f9c2&page=MyApp.BoardPage&protocol_version=1&policy_hash=0123456789abcdef&cursor=Nzc4LjA",
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

    it("stores the heartbeat interval the handshake announced", async () => {
      stubHandshakeResponse({heartbeatIntervalMs: 1_000});

      await Sse.connect();

      assert.strictEqual(Sse.heartbeatIntervalMs, 1_000);
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

      sinon.assert.calledWithExactly(loggerDebugStub, "SSE stream lost: error");
    });

    it("closes the failed EventSource", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledOnce(mockEventSource.close);
    });

    it("flips the sseConnected? signal to false on the global registry", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      // After the connect, which says so itself before the stream opens.
      const globalRegistrySetSpy = sinon.spy(GlobalRegistry, "set");

      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledWith(globalRegistrySetSpy, "sseConnected?", false);
    });

    // The log's session storage can be full, and the tab still has to get its stream back.
    it("schedules a reconnect when the log can't be written", async () => {
      loggerDebugStub.restore();

      sinon
        .stub(Object.getPrototypeOf(sessionStorage), "setItem")
        .throws(new DOMException("full", "QuotaExceededError"));

      stubHandshakeResponse();

      await Sse.connect();
      setTimeoutSpy.resetHistory();

      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledWith(
        setTimeoutSpy,
        sinon.match.func,
        Sse.BASE_RECONNECT_DELAY,
      );
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

      // A stream loss logs, and the log is kept in session storage, which a run of this file
      // alone has none of.
      sinon.stub(Logger, "debug");
    });

    // A stream replaced before it had lasted has earned nothing, and the count belongs to the one
    // replacing it.
    it("clears nothing for a stream replaced before it lasted", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onopen({});

      fetchStub.returns(new Promise(() => {}));

      Sse.reconnect();
      Sse.reconnectAttempts = 3;

      clock.tick(Sse.STABLE_CONNECTION_MS);

      assert.equal(Sse.reconnectAttempts, 3);
    });

    // The same for a stream another connect closed: the count belongs to the one that stands.
    it("clears nothing for a stream another connect closed before it lasted", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onopen({});

      await Sse.connect();
      Sse.reconnectAttempts = 3;

      clock.tick(Sse.STABLE_CONNECTION_MS);

      assert.equal(Sse.reconnectAttempts, 3);
    });

    // A batch whose send got no answer is still pending, and this is the one signal that means
    // the network is worth trying again.
    it("sends the pending batches again when the stream comes back", async () => {
      // A build that ships the data layer carries its sync constants.
      globalThis.Hologram.sync = {
        modelHash: "a3f9c2",
        policyHash: "0123456789abcdef",
        protocolVersion: 1,
      };
      setDataLayer();
      stubHandshakeResponse();

      const flushStub = sinon.stub(Batches, "flush");

      try {
        await Sse.connect();
        Sse.eventSource.onopen({});
      } finally {
        delete globalThis.Hologram.sync;
      }

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

  // Browsers never surface a stream that died without being closed, so the client
  // keeps its own clock on the heartbeat.
  describe("heartbeat watchdog", () => {
    let clock;
    let loggerDebugStub;

    beforeEach(() => {
      clock = sinon.useFakeTimers();
      loggerDebugStub = sinon.stub(Logger, "debug");
      stubHandshakeResponse({heartbeatIntervalMs: 1_000});
    });

    it("ends the stream once the timeout passes with no heartbeat", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS);

      sinon.assert.calledOnce(mockEventSource.close);
    });

    it("is cancelled when the browser reports the error first", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});
      Sse.eventSource.onerror({type: "error"});

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS * 2);

      sinon.assert.calledOnce(mockEventSource.close);
    });

    // The stream it watched is closed, and a new handshake may still be on its way.
    it("is cancelled when the stream is replaced on purpose", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      fetchStub.returns(new Promise(() => {}));

      Sse.reconnect();

      assert.doesNotThrow(() =>
        clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS * 2),
      );

      sinon.assert.calledOnce(mockEventSource.close);
      sinon.assert.calledTwice(fetchStub);
      assert.equal(Sse.reconnectAttempts, 0);
    });

    // Left armed, it would end the replacement at the old stream's deadline.
    it("leaves alone the stream that replaced the one it watched", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      await Sse.reconnect();

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS);

      sinon.assert.calledOnce(mockEventSource.close);
      assert.equal(Sse.reconnectAttempts, 0);
    });

    // Two connects in flight: the second closes the first's stream, whose watchdog must not go on
    // to end the second's.
    it("is cancelled when another connect closes the stream", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      await Sse.connect();

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS);

      sinon.assert.calledOnce(mockEventSource.close);
    });

    it("leaves the stream alone until the timeout has fully elapsed", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS - 1);

      sinon.assert.notCalled(mockEventSource.close);
    });

    it("pushes the deadline on every heartbeat", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      clock.tick(1_500);
      mockEventSource.listeners.heartbeat({});
      clock.tick(1_500);

      sinon.assert.notCalled(mockEventSource.close);

      clock.tick(500);

      sinon.assert.calledOnce(mockEventSource.close);
    });

    it("reconnects the way a browser-reported error does", async () => {
      await Sse.connect();
      Sse.eventSource.onopen({});

      // After the stream opened, so what it records is the loss.
      const globalRegistrySetSpy = sinon.spy(GlobalRegistry, "set");

      clock.tick(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS);

      sinon.assert.calledWith(globalRegistrySetSpy, "sseConnected?", false);
      assert.strictEqual(Sse.reconnectAttempts, 1);

      sinon.assert.calledWithExactly(
        loggerDebugStub,
        "SSE stream lost: heartbeat timeout",
      );
    });
  });

  describe("page lifecycle", () => {
    let clock;

    beforeEach(() => {
      clock = sinon.useFakeTimers();

      // A stream loss logs, and the log is kept in session storage, which a run of this file
      // alone has none of.
      sinon.stub(Logger, "debug");
    });

    describe("start()", () => {
      it("opens the stream on the first call", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.runAllAsync();

        sinon.assert.calledOnce(fetchStub);
        sinon.assert.calledOnce(globalThis.EventSource);
      });

      it("does nothing on a second call while the first handshake is in flight", async () => {
        stubHandshakeResponse();

        Sse.start();
        Sse.start();
        await clock.runAllAsync();

        sinon.assert.calledOnce(fetchStub);
        sinon.assert.calledOnce(globalThis.EventSource);
      });

      it("does nothing on a second call while a failed handshake waits for its retry", async () => {
        fetchStub.rejects(new Error("network down"));

        Sse.start();
        await clock.tickAsync(0);

        Sse.start();
        await clock.tickAsync(0);

        sinon.assert.calledOnce(fetchStub);
        assert.strictEqual(Sse.reconnectAttempts, 1);
      });

      it("does nothing on a second call once the stream is open", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.start();
        await clock.tickAsync(0);

        sinon.assert.calledOnce(fetchStub);
      });

      it("does not open the stream on a page that has been left", async () => {
        stubHandshakeResponse();

        Sse.suspend();
        Sse.start();
        await clock.runAllAsync();

        sinon.assert.notCalled(fetchStub);
        sinon.assert.notCalled(globalThis.EventSource);
      });
    });

    describe("suspend()", () => {
      it("closes the stream", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.suspend();

        sinon.assert.calledOnce(mockEventSource.close);
      });

      it("does not throw when no stream was opened", () => {
        assert.doesNotThrow(() => Sse.suspend());
      });

      it("flips the sseConnected? signal to false on the global registry", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.suspend();

        assert.isFalse(globalThis.Hologram["sseConnected?"]);
      });

      it("cancels the heartbeat watchdog", async () => {
        stubHandshakeResponse({heartbeatIntervalMs: 1_000});

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.suspend();
        await clock.tickAsync(1_000 * Sse.HEARTBEAT_TIMEOUT_INTERVALS * 2);

        // A stream loss would close the stream a second time and retry the handshake.
        sinon.assert.calledOnce(mockEventSource.close);
        sinon.assert.calledOnce(fetchStub);
      });

      it("cancels the pending clear of the failure count", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.suspend();
        Sse.reconnectAttempts = 3;
        await clock.tickAsync(Sse.STABLE_CONNECTION_MS * 2);

        assert.strictEqual(Sse.reconnectAttempts, 3);
      });

      it("cancels a pending reconnect", async () => {
        fetchStub.rejects(new Error("network down"));

        Sse.start();
        await clock.tickAsync(0);

        Sse.suspend();
        await clock.tickAsync(Sse.MAX_RECONNECT_DELAY * 2);

        sinon.assert.calledOnce(fetchStub);
      });

      it("forgets the failures counted so far", async () => {
        fetchStub.rejects(new Error("network down"));

        Sse.start();
        await clock.tickAsync(0);
        assert.strictEqual(Sse.reconnectAttempts, 1);

        Sse.suspend();

        assert.strictEqual(Sse.reconnectAttempts, 0);
      });

      it("keeps a handshake in flight from opening a stream", async () => {
        stubHandshakeResponse();

        Sse.start();
        Sse.suspend();
        await clock.runAllAsync();

        sinon.assert.calledOnce(fetchStub);
        sinon.assert.notCalled(globalThis.EventSource);
      });

      it("keeps a handshake whose response is still being read from opening a stream", async () => {
        let resolveJson;

        fetchStub.resolves({
          ok: true,
          status: 200,
          json: () => new Promise((resolve) => (resolveJson = resolve)),
        });

        const deserializeStub = sinon.stub(Deserializer, "deserialize");

        Sse.start();
        await clock.tickAsync(0);

        Sse.suspend();

        resolveJson({
          handshakeId: "test-handshake-id",
          heartbeatIntervalMs: 15_000,
          refreshedReceipts: serializedValue(Type.list()),
        });

        await clock.runAllAsync();

        sinon.assert.notCalled(deserializeStub);
        sinon.assert.notCalled(globalThis.EventSource);
      });

      it("keeps a handshake in flight that then fails from scheduling a reconnect", async () => {
        fetchStub.rejects(new Error("aborted"));

        Sse.start();
        Sse.suspend();
        await clock.runAllAsync();

        sinon.assert.calledOnce(fetchStub);
        assert.strictEqual(Sse.reconnectAttempts, 0);
      });

      it("keeps a handshake in flight that then gets a non-2xx from scheduling a reconnect", async () => {
        stubHandshakeResponse({ok: false, status: 503});

        Sse.start();
        Sse.suspend();
        await clock.runAllAsync();

        sinon.assert.calledOnce(fetchStub);
        assert.strictEqual(Sse.reconnectAttempts, 0);
      });
    });

    describe("resume()", () => {
      it("reopens the stream that suspend() closed", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);
        Sse.eventSource.onopen({});

        Sse.suspend();
        Sse.resume();
        await clock.tickAsync(0);

        sinon.assert.calledTwice(fetchStub);
        sinon.assert.calledTwice(globalThis.EventSource);
      });

      it("does nothing when the page was not left", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);

        Sse.resume();
        await clock.tickAsync(0);

        sinon.assert.calledOnce(fetchStub);
      });

      it("does nothing on a second call", async () => {
        stubHandshakeResponse();

        Sse.start();
        await clock.tickAsync(0);

        Sse.suspend();
        Sse.resume();
        Sse.resume();
        await clock.tickAsync(0);

        sinon.assert.calledTwice(fetchStub);
        sinon.assert.calledTwice(globalThis.EventSource);
      });

      it("leaves opening the stream to start() on a page left before its first mount", async () => {
        stubHandshakeResponse();

        Sse.suspend();
        Sse.resume();
        await clock.tickAsync(0);

        sinon.assert.notCalled(fetchStub);

        Sse.start();
        await clock.tickAsync(0);

        sinon.assert.calledOnce(fetchStub);
        sinon.assert.calledOnce(globalThis.EventSource);
      });

      it("opens a single stream, from its own handshake, when one from before suspend() is still in flight", async () => {
        stubHandshakeResponse();

        const response = (handshakeId) => ({
          ok: true,
          status: 200,
          json: async () => ({
            handshakeId,
            heartbeatIntervalMs: 15_000,
            refreshedReceipts: serializedValue(Type.list()),
          }),
        });

        fetchStub.onFirstCall().resolves(response("stale-handshake-id"));
        fetchStub.onSecondCall().resolves(response("fresh-handshake-id"));

        Sse.start();
        Sse.suspend();
        Sse.resume();
        await clock.runAllAsync();

        sinon.assert.calledTwice(fetchStub);

        sinon.assert.calledOnceWithExactly(
          globalThis.EventSource,
          "/hologram/sse?instance_id=test-instance-id&handshake_id=fresh-handshake-id",
        );
      });
    });
  });

  describe("onopen", () => {
    // Opening arms the heartbeat watchdog. A fake clock keeps it from outliving the test.
    beforeEach(() => {
      sinon.useFakeTimers();
    });

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

      stubHandshakeResponse();

      const scheduleStub = sinon.stub(Hologram, "schedulePushedAction");

      await Sse.connect();

      const serializedDecodedAction = serializedValue(decodedAction);

      Sse.eventSource.listeners.action({
        data: JSON.stringify({
          action: serializedDecodedAction,
          chunks: ["AAAAAAAA", "BBBBBBBB"],
        }),
      });

      sinon.assert.calledOnceWithExactly(scheduleStub, decodedAction, [
        "AAAAAAAA",
        "BBBBBBBB",
      ]);
    });

    it("silently drops the action when the target cid is not mounted", async () => {
      const decodedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        target: Type.bitstring("c_unmounted"),
      });

      stubHandshakeResponse();

      const scheduleStub = sinon.stub(Hologram, "schedulePushedAction");

      await Sse.connect();

      const serializedDecodedAction = serializedValue(decodedAction);

      Sse.eventSource.listeners.action({
        data: JSON.stringify({
          action: serializedDecodedAction,
          chunks: [],
        }),
      });

      sinon.assert.notCalled(scheduleStub);
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

      stubHandshakeResponse();

      const scheduleStub = sinon.stub(Hologram, "schedulePushedAction");

      await Sse.connect();

      const serializedEnvelope = serializedValue(envelope);

      Sse.eventSource.listeners.broadcast({
        data: JSON.stringify({
          chunks: ["AAAAAAAA", "BBBBBBBB"],
          data: serializedEnvelope,
        }),
      });

      assert.deepStrictEqual(scheduleStub.args, [
        [
          Type.actionStruct({name: actionName, params: params, target: chat}),
          ["AAAAAAAA", "BBBBBBBB"],
        ],
        [
          Type.actionStruct({
            name: actionName,
            params: params,
            target: sidebar,
          }),
          ["AAAAAAAA", "BBBBBBBB"],
        ],
      ]);
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

      stubHandshakeResponse();

      const scheduleStub = sinon.stub(Hologram, "schedulePushedAction");

      await Sse.connect();

      const serializedEnvelope = serializedValue(envelope);

      Sse.eventSource.listeners.broadcast({
        data: JSON.stringify({chunks: [], data: serializedEnvelope}),
      });

      sinon.assert.calledOnceWithExactly(
        scheduleStub,
        Type.actionStruct({name: actionName, params: params, target: chat}),
        [],
      );
    });

    it("is a no-op when the cids list is empty", async () => {
      const envelope = Type.tuple([
        Type.atom("my_action"),
        Type.map([]),
        Type.list([]),
      ]);

      stubHandshakeResponse();

      const scheduleStub = sinon.stub(Hologram, "schedulePushedAction");

      await Sse.connect();

      const serializedEnvelope = serializedValue(envelope);

      Sse.eventSource.listeners.broadcast({
        data: JSON.stringify({chunks: [], data: serializedEnvelope}),
      });

      sinon.assert.notCalled(scheduleStub);
    });
  });

  describe("compilation_error event", () => {
    it("shows the overlay with the parsed lines", async () => {
      stubHandshakeResponse();
      const showStub = sinon.stub(LiveReload, "showErrorOverlay");

      await Sse.connect();

      Sse.eventSource.listeners.compilation_error({
        data: '[[{"text":"boom","tone":"banner"}]]',
      });

      sinon.assert.calledOnceWithExactly(showStub, [
        [{text: "boom", tone: "banner"}],
      ]);
    });
  });

  describe("compiled event", () => {
    it("takes the compilation error overlay down", async () => {
      stubHandshakeResponse();
      const hideStub = sinon.stub(LiveReload, "hideErrorOverlay");

      await Sse.connect();

      Sse.eventSource.listeners.compiled({data: ""});

      sinon.assert.calledOnceWithExactly(hideStub);
    });
  });

  describe("css_changed event", () => {
    it("swaps the page's stylesheets with the app's asset paths it carries", async () => {
      stubHandshakeResponse();
      const swapStub = sinon.stub(LiveReload, "swapStylesheets");

      await Sse.connect();

      Sse.eventSource.listeners.css_changed({
        data: '{"assets/app.css":"/assets/app.css"}',
      });

      sinon.assert.calledOnceWithExactly(swapStub, {
        "assets/app.css": "/assets/app.css",
      });
    });
  });

  describe("add_sub_receipts event", () => {
    it("inserts new entries and leaves non-matching entries intact", async () => {
      const adds = Type.list([receiptA]);

      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      const serializedAdds = serializedText(adds);

      Sse.eventSource.listeners.add_sub_receipts({data: serializedAdds});

      assert.deepStrictEqual(
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

      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, oldReceiptA);

      const serializedAdds = serializedText(adds);

      Sse.eventSource.listeners.add_sub_receipts({data: serializedAdds});

      assert.deepStrictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        newReceiptA,
      );
    });

    it("is a no-op when the receipts list is empty", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);

      const serializedEmptyList = serializedText(Type.list());

      Sse.eventSource.listeners.add_sub_receipts({
        data: serializedEmptyList,
      });

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        receiptA,
      );
    });
  });

  describe("drop_sub_receipts event", () => {
    it("purges the named entries from the receipt registry", async () => {
      const dropBindings = Type.list([bindingA]);

      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);
      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      const serializedDropBindings = serializedText(dropBindings);

      Sse.eventSource.listeners.drop_sub_receipts({
        data: serializedDropBindings,
      });

      assert.isFalse(SubscriptionReceiptRegistry.entries.has(encodedBindingA));
      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedBindingB));
    });

    it("is a no-op when the keys list is empty", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, receiptA);

      const serializedEmptyList = serializedText(Type.list());

      Sse.eventSource.listeners.drop_sub_receipts({
        data: serializedEmptyList,
      });

      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedBindingA));
    });
  });

  describe("refresh_sub_receipts event", () => {
    const staleReceiptA = receipt(Type.atom("room_a"), "page", "stale-token-a");
    const freshReceiptA = receipt(Type.atom("room_a"), "page", "fresh-token-a");

    it("replaces matching entries with refreshed receipts and leaves non-matching entries intact", async () => {
      const refreshed = Type.list([freshReceiptA]);

      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, staleReceiptA);
      SubscriptionReceiptRegistry.entries.set(encodedBindingB, receiptB);

      const serializedRefreshed = serializedText(refreshed);

      Sse.eventSource.listeners.refresh_sub_receipts({
        data: serializedRefreshed,
      });

      assert.deepStrictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        freshReceiptA,
      );

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingB),
        receiptB,
      );
    });

    it("is a no-op when the receipts list is empty", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedBindingA, staleReceiptA);

      const serializedEmptyList = serializedText(Type.list());

      Sse.eventSource.listeners.refresh_sub_receipts({
        data: serializedEmptyList,
      });

      assert.strictEqual(
        SubscriptionReceiptRegistry.entries.get(encodedBindingA),
        staleReceiptA,
      );
    });
  });

  describe("reload event", () => {
    it("hands the parsed pages and the page shown to live reload", async () => {
      stubHandshakeResponse();

      const pageModule = Type.atom("Elixir.MyApp.Page1");
      sinon.stub(Hologram, "pageModule").returns(pageModule);
      const handleReloadStub = sinon.stub(LiveReload, "handleReload");

      await Sse.connect();

      Sse.eventSource.listeners.reload({data: '["Elixir.MyApp.Page1"]'});

      sinon.assert.calledOnceWithExactly(
        handleReloadStub,
        ["Elixir.MyApp.Page1"],
        pageModule,
      );
    });

    it("hands over all when every tab must reload", async () => {
      stubHandshakeResponse();

      sinon
        .stub(Hologram, "pageModule")
        .returns(Type.atom("Elixir.MyApp.Page1"));
      const handleReloadStub = sinon.stub(LiveReload, "handleReload");

      await Sse.connect();

      Sse.eventSource.listeners.reload({data: '"all"'});

      sinon.assert.calledOnce(handleReloadStub);
      assert.strictEqual(handleReloadStub.firstCall.args[0], "all");
    });
  });
});

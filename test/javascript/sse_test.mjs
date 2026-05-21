"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  initComponentRegistryEntry,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Logger from "../../assets/js/logger.mjs";
import Sse from "../../assets/js/sse.mjs";
import SubscriptionReceiptRegistry from "../../assets/js/subscription_receipt_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  let fetchStub;
  let mockEventSource;
  let originalInstanceId;

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

    globalThis.window = {location: {reload: sinon.spy()}};

    originalInstanceId = App.instanceId;
    App.instanceId = "test-instance-id";
  });

  afterEach(() => {
    sinon.restore();

    delete globalThis.EventSource;
    delete globalThis.window;

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

    it("does not open an EventSource when fetch throws", async () => {
      fetchStub.rejects(new Error("network down"));

      await Sse.connect();

      sinon.assert.notCalled(globalThis.EventSource);
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

  describe("onopen", () => {
    it("resets reconnectAttempts to 0", async () => {
      stubHandshakeResponse();

      await Sse.connect();

      Sse.reconnectAttempts = 5;
      Sse.eventSource.onopen({});

      assert.strictEqual(Sse.reconnectAttempts, 0);
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

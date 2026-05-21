"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  initComponentRegistryEntry,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
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
    SubscriptionReceiptRegistry.entries.clear();

    mockEventSource = {
      close: sinon.spy(),
      listeners: {},
      addEventListener: function (type, listener) {
        this.listeners[type] = listener;
      },
      onerror: null,
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

    it("extracts the token from each stored receipt triple", () => {
      const tripleA = Type.tuple([
        Type.atom("room_a"),
        Type.bitstring("page"),
        Type.bitstring("token-a"),
      ]);

      const tripleB = Type.tuple([
        Type.atom("room_b"),
        Type.bitstring("widget"),
        Type.bitstring("token-b"),
      ]);

      SubscriptionReceiptRegistry.entries.set("key-a", tripleA);
      SubscriptionReceiptRegistry.entries.set("key-b", tripleB);

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
        Type.tuple([
          Type.atom("room_a"),
          Type.bitstring("page"),
          Type.bitstring("fresh-token"),
        ]),
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
        Type.tuple([
          Type.atom("room_a"),
          Type.bitstring("page"),
          Type.bitstring("stale-token"),
        ]),
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
        Type.tuple([
          Type.atom("room_a"),
          Type.bitstring("page"),
          Type.bitstring("stale-token"),
        ]),
      );

      const refreshedReceipts = Type.list([
        Type.tuple([
          Type.atom("room_a"),
          Type.bitstring("page"),
          Type.bitstring("fresh-token"),
        ]),
      ]);

      stubHandshakeResponse({refreshedReceipts});

      await Sse.connect();

      sinon.assert.notCalled(globalThis.window.location.reload);
      sinon.assert.calledOnce(globalThis.EventSource);
    });
  });

  describe("onerror", () => {
    it("logs the error", async () => {
      stubHandshakeResponse();

      const loggerDebugStub = sinon.stub(Logger, "debug");

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledWithExactly(loggerDebugStub, "SSE error: error");
    });

    it("does not close the EventSource", async () => {
      stubHandshakeResponse();

      await Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.notCalled(mockEventSource.close);
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

  describe("drop_sub_receipts event", () => {
    const tripleA = Type.tuple([
      Type.atom("room_a"),
      Type.bitstring("page"),
      Type.bitstring("token-a"),
    ]);

    const tripleB = Type.tuple([
      Type.atom("room_b"),
      Type.bitstring("widget"),
      Type.bitstring("token-b"),
    ]);

    const encodedKeyA = Type.encodeMapKey(
      Type.tuple([Type.atom("room_a"), Type.bitstring("page")]),
    );

    const encodedKeyB = Type.encodeMapKey(
      Type.tuple([Type.atom("room_b"), Type.bitstring("widget")]),
    );

    it("purges the named entries from the receipt registry", async () => {
      const dropKeys = Type.list([
        Type.tuple([Type.atom("room_a"), Type.bitstring("page")]),
      ]);

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-drop-keys").returns(dropKeys);

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedKeyA, tripleA);
      SubscriptionReceiptRegistry.entries.set(encodedKeyB, tripleB);

      Sse.eventSource.listeners.drop_sub_receipts({data: "encoded-drop-keys"});

      assert.isFalse(SubscriptionReceiptRegistry.entries.has(encodedKeyA));
      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedKeyB));
    });

    it("is a no-op when the keys list is empty", async () => {
      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-drop-keys").returns(Type.list());

      await Sse.connect();

      SubscriptionReceiptRegistry.entries.set(encodedKeyA, tripleA);

      Sse.eventSource.listeners.drop_sub_receipts({data: "encoded-drop-keys"});

      assert.isTrue(SubscriptionReceiptRegistry.entries.has(encodedKeyA));
    });
  });
});

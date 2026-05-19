"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Logger from "../../assets/js/logger.mjs";
import Sse from "../../assets/js/sse.mjs";
import SubscriptionReceiptRegistry from "../../assets/js/subscription_receipt_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  let mockEventSource;
  let originalInstanceId;
  let fetchStub;

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
    Sse.eventSource = null;
    SubscriptionReceiptRegistry.entries.clear();

    mockEventSource = {
      close: sinon.spy(),
      onmessage: null,
      onerror: null,
    };

    globalThis.EventSource = sinon.stub().returns(mockEventSource);
    fetchStub = sinon.stub(globalThis, "fetch");

    originalInstanceId = App.instanceId;
    App.instanceId = "test-instance-id";
  });

  afterEach(() => {
    sinon.restore();
    delete globalThis.EventSource;
    App.instanceId = originalInstanceId;
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

  describe("onmessage", () => {
    it("decodes the event data and schedules the resulting action", async () => {
      const decodedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        target: Type.bitstring("c1"),
      });

      const evalStub = stubHandshakeResponse();
      evalStub.withArgs("encoded-action-expression").returns(decodedAction);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      await Sse.connect();
      Sse.eventSource.onmessage({data: "encoded-action-expression"});

      sinon.assert.calledWith(evalStub, "encoded-action-expression");

      sinon.assert.calledOnceWithExactly(scheduleStub, decodedAction);
    });
  });
});

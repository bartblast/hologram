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
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  let mockEventSource;
  let originalInstanceId;

  beforeEach(() => {
    Sse.eventSource = null;

    mockEventSource = {
      close: sinon.spy(),
      onmessage: null,
      onerror: null,
    };

    globalThis.EventSource = sinon.stub().returns(mockEventSource);

    originalInstanceId = App.instanceId;
    App.instanceId = "test-instance-id";
  });

  afterEach(() => {
    sinon.restore();
    delete globalThis.EventSource;

    App.instanceId = originalInstanceId;
  });

  describe("connect()", () => {
    it("instantiates an EventSource at the SSE path with the current instance_id", () => {
      Sse.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse?instance_id=test-instance-id",
      );
    });

    it("stores the EventSource instance on the static field", () => {
      Sse.connect();

      assert.strictEqual(Sse.eventSource, mockEventSource);
    });
  });

  describe("onerror", () => {
    it("logs the error", () => {
      const loggerDebugStub = sinon.stub(Logger, "debug");

      Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledOnceWithExactly(loggerDebugStub, "SSE error: error");
    });

    it("does not close the EventSource (relies on native browser reconnect)", () => {
      Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.notCalled(mockEventSource.close);
    });
  });

  describe("onmessage", () => {
    it("decodes the event data and schedules the resulting action", () => {
      const decodedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        target: Type.bitstring("c1"),
      });

      const evalStub = sinon
        .stub(Interpreter, "evaluateJavaScriptExpression")
        .returns(decodedAction);

      const scheduleStub = sinon.stub(Hologram, "scheduleAction");

      Sse.connect();
      Sse.eventSource.onmessage({data: "encoded-action-expression"});

      sinon.assert.calledOnceWithExactly(evalStub, "encoded-action-expression");

      sinon.assert.calledOnceWithExactly(scheduleStub, decodedAction);
    });
  });
});

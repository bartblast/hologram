"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Logger from "../../assets/js/logger.mjs";
import Sse from "../../assets/js/sse.mjs";

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

    it("assigns an onmessage handler that logs the event data", () => {
      const loggerDebugStub = sinon.stub(Logger, "debug");

      Sse.connect();
      Sse.eventSource.onmessage({data: "hello"});

      sinon.assert.calledOnceWithExactly(loggerDebugStub, "SSE event: hello");
    });

    it("assigns an onerror handler that logs the error", () => {
      const loggerDebugStub = sinon.stub(Logger, "debug");

      Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.calledOnceWithExactly(loggerDebugStub, "SSE error: error");
    });

    it("does not close the EventSource on error (relies on native browser reconnect)", () => {
      Sse.connect();
      Sse.eventSource.onerror({type: "error"});

      sinon.assert.notCalled(mockEventSource.close);
    });
  });
});

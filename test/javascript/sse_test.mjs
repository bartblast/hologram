"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import Logger from "../../assets/js/logger.mjs";
import Sse from "../../assets/js/sse.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  let mockEventSource;

  beforeEach(() => {
    Sse.eventSource = null;

    mockEventSource = {
      close: sinon.spy(),
      onmessage: null,
      onerror: null,
    };

    globalThis.EventSource = sinon.stub().returns(mockEventSource);
  });

  afterEach(() => {
    sinon.restore();
    delete globalThis.EventSource;
  });

  describe("connect()", () => {
    it("instantiates an EventSource at the SSE path", () => {
      Sse.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.EventSource,
        "/hologram/sse",
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
  });
});

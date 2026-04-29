"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import Sse from "../../assets/js/sse.mjs";

defineGlobalErlangAndElixirModules();

describe("Sse", () => {
  let mockEventSource;

  beforeEach(() => {
    Sse.eventSource = null;
    Sse.status = "disconnected";

    mockEventSource = {
      onopen: null,
      onerror: null,
      onmessage: null,
      close: sinon.spy(),
    };

    globalThis.EventSource = sinon.stub().returns(mockEventSource);
  });

  afterEach(() => {
    sinon.restore();
  });

  describe("connect()", () => {
    it("creates an EventSource at the SSE path", () => {
      Sse.connect();

      sinon.assert.calledWith(globalThis.EventSource, "/hologram/sse");
    });

    it("wires onopen, onerror and onmessage handlers", () => {
      Sse.connect();

      assert.equal(mockEventSource.onopen, Sse.handleOpen);
      assert.equal(mockEventSource.onerror, Sse.handleError);
      assert.equal(mockEventSource.onmessage, Sse.handleMessage);
    });

    it("sets status to connecting", () => {
      Sse.connect();

      assert.equal(Sse.status, "connecting");
    });

    it("returns early when already connected", () => {
      Sse.status = "connected";
      Sse.connect();

      sinon.assert.notCalled(globalThis.EventSource);
    });

    it("returns early when already connecting", () => {
      Sse.status = "connecting";
      Sse.connect();

      sinon.assert.notCalled(globalThis.EventSource);
    });
  });

  describe("handleError()", () => {
    it("sets status to error", () => {
      sinon.stub(console, "warn");
      Sse.handleError({});

      assert.equal(Sse.status, "error");
    });
  });

  describe("handleMessage()", () => {
    it("logs the message data", () => {
      const consoleLog = sinon.stub(console, "log");
      Sse.handleMessage({data: "test-data"});

      sinon.assert.calledWith(consoleLog, "Hologram: SSE message", "test-data");
    });
  });

  describe("handleOpen()", () => {
    it("sets status to connected", () => {
      sinon.stub(console, "log");
      Sse.handleOpen({});

      assert.equal(Sse.status, "connected");
    });
  });

  describe("isConnected()", () => {
    it("returns true when status is connected", () => {
      Sse.status = "connected";

      assert.isTrue(Sse.isConnected());
    });

    it("returns false when status is anything other than connected", () => {
      Sse.status = "disconnected";
      assert.isFalse(Sse.isConnected());

      Sse.status = "connecting";
      assert.isFalse(Sse.isConnected());

      Sse.status = "error";
      assert.isFalse(Sse.isConnected());
    });
  });
});

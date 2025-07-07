"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
  sinon,
} from "./support/helpers.mjs";

import Connection from "../../assets/js/connection.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

describe("Connection", () => {
  let clock;
  let mockWebSocket;

  beforeEach(() => {
    Connection.websocket = null;
    Connection.status = "disconnected";
    Connection.reconnectAttempts = 0;

    Connection.clearConnectionTimer();
    Connection.clearReconnectTimer();
    Connection.clearPingTimer();
    Connection.clearPongTimer();
    Connection.clearPendingRequests(false);

    sinon.stub(GlobalRegistry, "set");
    clock = sinon.useFakeTimers();

    mockWebSocket = {
      onopen: null,
      onclose: null,
      onerror: null,
      onmessage: null,
      close: sinon.spy(),
      send: sinon.spy(),
      readyState: WebSocket.CONNECTING,
    };

    const connecting = WebSocket.CONNECTING;
    const open = WebSocket.OPEN;
    const closing = WebSocket.CLOSING;
    const closed = WebSocket.CLOSED;

    globalThis.WebSocket = sinon.stub().returns(mockWebSocket);
    globalThis.WebSocket.CONNECTING = connecting;
    globalThis.WebSocket.OPEN = open;
    globalThis.WebSocket.CLOSING = closing;
    globalThis.WebSocket.CLOSED = closed;
  });

  afterEach(() => {
    clock.restore();
    sinon.restore();
  });

  describe("clearConnectionTimer()", () => {
    it("clears the connection timer when it exists", () => {
      Connection.connectionTimer = setTimeout(() => {}, 10_000);
      Connection.clearConnectionTimer();

      assert.isNull(Connection.connectionTimer);
    });

    it("does nothing when connection timer is null", () => {
      Connection.connectionTimer = null;
      Connection.clearConnectionTimer();

      assert.isNull(Connection.connectionTimer);
    });
  });

  describe("clearPendingRequests()", () => {
    it("clears all pending requests without triggering error callbacks", () => {
      const onError1 = sinon.spy();
      const onError2 = sinon.spy();

      Connection.pendingRequests.set("request1", {
        timerId: setTimeout(() => {}, 10_000),
        onError: onError1,
      });

      Connection.pendingRequests.set("request2", {
        timerId: setTimeout(() => {}, 10_000),
        onError: onError2,
      });

      Connection.clearPendingRequests(false);

      assert.equal(Connection.pendingRequests.size, 0);

      sinon.assert.notCalled(onError1);
      sinon.assert.notCalled(onError2);
    });

    it("clears all pending requests and triggers error callbacks", () => {
      const onError1 = sinon.spy();
      const onError2 = sinon.spy();

      Connection.pendingRequests.set("request1", {
        timerId: setTimeout(() => {}, 10_000),
        onError: onError1,
      });

      Connection.pendingRequests.set("request2", {
        timerId: setTimeout(() => {}, 10_000),
        onError: onError2,
      });

      Connection.clearPendingRequests(true);

      assert.equal(Connection.pendingRequests.size, 0);

      sinon.assert.calledOnce(onError1);
      sinon.assert.calledOnce(onError2);
    });
  });

  describe("clearPingTimer()", () => {
    it("clears the ping timer when it exists", () => {
      Connection.pingTimer = setInterval(() => {}, 10_000);
      Connection.clearPingTimer();

      assert.isNull(Connection.pingTimer);
    });

    it("does nothing when ping timer is null", () => {
      Connection.pingTimer = null;
      Connection.clearPingTimer();

      assert.isNull(Connection.pingTimer);
    });
  });

  describe("clearPongTimer()", () => {
    it("clears the pong timer when it exists", () => {
      Connection.pongTimer = setTimeout(() => {}, 10_000);
      Connection.clearPongTimer();

      assert.isNull(Connection.pongTimer);
    });

    it("does nothing when pong timer is null", () => {
      Connection.pongTimer = null;
      Connection.clearPongTimer();

      assert.isNull(Connection.pongTimer);
    });
  });

  describe("clearReconnectTimer()", () => {
    it("clears the reconnect timer when it exists", () => {
      Connection.reconnectTimer = setTimeout(() => {}, 10_000);
      Connection.clearReconnectTimer();

      assert.isNull(Connection.reconnectTimer);
    });

    it("does nothing when reconnect timer is null", () => {
      Connection.reconnectTimer = null;
      Connection.clearReconnectTimer();

      assert.isNull(Connection.reconnectTimer);
    });
  });

  describe("connect()", () => {
    it("does not connect when already connected", () => {
      Connection.status = "connected";
      Connection.connect();

      sinon.assert.notCalled(globalThis.WebSocket);
    });

    it("does not connect when already connecting", () => {
      Connection.status = "connecting";
      Connection.connect();

      sinon.assert.notCalled(globalThis.WebSocket);
    });

    it("creates websocket connection and sets up handlers", () => {
      Connection.connect();

      sinon.assert.calledOnceWithExactly(
        globalThis.WebSocket,
        "/hologram/websocket",
      );
      assert.equal(Connection.status, "connecting");
      assert.equal(Connection.websocket, mockWebSocket);
      assert.isFunction(mockWebSocket.onopen);
      assert.isFunction(mockWebSocket.onclose);
      assert.isFunction(mockWebSocket.onerror);
      assert.isFunction(mockWebSocket.onmessage);
    });

    it("sets connection timer", () => {
      Connection.connect();

      assert.isNotNull(Connection.connectionTimer);
    });

    it("handles connection timeout", () => {
      Connection.connect();

      clock.tick(Connection.CONNECTION_TIMEOUT);

      sinon.assert.calledOnce(mockWebSocket.close);
      assert.equal(Connection.status, "error");
    });

    it("handles WebSocket constructor errors", () => {
      globalThis.WebSocket = sinon.stub().throws(new Error("WebSocket error"));

      Connection.connect();

      assert.equal(Connection.status, "error");
    });
  });

  describe("encodeMessage()", () => {
    it("encodes type-only message", () => {
      const result = Connection.encodeMessage("ping", null, null);
      assert.equal(result, '"ping"');
    });

    it("encodes message with payload but no correlation ID", () => {
      const payload = Type.atom("abc");
      const serialized = Serializer.serialize(payload, "server");

      const result = Connection.encodeMessage("test", payload, null);

      assert.equal(result, `["test",${serialized}]`);
    });

    it("encodes message with payload and correlation ID", () => {
      const payload = Type.atom("abc");
      const serialized = Serializer.serialize(payload, "server");
      const correlationId = "123";

      const result = Connection.encodeMessage("test", payload, correlationId);

      assert.equal(result, `["test",${serialized},"123"]`);
    });
  });

  describe("handleClose()", () => {
    const event = {code: 1_000, reason: "Normal closure"};
    let consoleWarnStub;

    beforeEach(() => {
      consoleWarnStub = sinon.stub(console, "warn");
    });

    afterEach(() => {
      consoleWarnStub.restore();
    });

    it("logs warning, updates status, and sets global registry", () => {
      Connection.handleClose(event);

      sinon.assert.calledWith(
        consoleWarnStub,
        "Hologram: disconnected from server",
        event,
      );

      assert.equal(Connection.status, "disconnected");
      sinon.assert.calledWith(GlobalRegistry.set, "connected?", false);
    });

    it("clears timers and pending requests", () => {
      Connection.connectionTimer = setTimeout(() => {}, 10_000);
      Connection.pingTimer = setInterval(() => {}, 10_000);
      Connection.pongTimer = setTimeout(() => {}, 10_000);

      const onError = sinon.spy();

      Connection.pendingRequests.set("request1", {
        timerId: setTimeout(() => {}, 10_000),
        onError,
      });

      Connection.handleClose(event);

      assert.isNull(Connection.connectionTimer);
      assert.isNull(Connection.pingTimer);
      assert.isNull(Connection.pongTimer);
      assert.equal(Connection.pendingRequests.size, 0);
      sinon.assert.calledOnce(onError);
    });

    it("triggers reconnection", () => {
      const reconnectSpy = sinon.spy(Connection, "reconnect");

      Connection.handleClose(event);

      sinon.assert.calledOnce(reconnectSpy);
    });
  });

  describe("handleConnectionTimeout()", () => {
    let consoleErrorStub;

    beforeEach(() => {
      consoleErrorStub = sinon.stub(console, "error");
    });

    afterEach(() => {
      consoleErrorStub.restore();
    });

    it("logs error and updates status", () => {
      Connection.handleConnectionTimeout();

      sinon.assert.calledWith(
        consoleErrorStub,
        "Hologram: server connection timeout",
      );
      assert.equal(Connection.status, "error");
    });

    it("triggers reconnection", () => {
      const reconnectSpy = sinon.spy(Connection, "reconnect");

      Connection.handleConnectionTimeout();

      sinon.assert.calledOnce(reconnectSpy);
    });
  });

  describe("handleError()", () => {
    const event = {type: "error"};
    let consoleErrorStub;

    beforeEach(() => {
      consoleErrorStub = sinon.stub(console, "error");
    });

    afterEach(() => {
      consoleErrorStub.restore();
    });

    it("logs error, updates status, and sets global registry", () => {
      Connection.handleError(event);

      sinon.assert.calledWith(
        consoleErrorStub,
        "Hologram: server connection error",
        event,
      );

      assert.equal(Connection.status, "error");
      sinon.assert.calledWith(GlobalRegistry.set, "connected?", false);
    });

    it("clears connection timer and triggers reconnection", () => {
      Connection.connectionTimer = setTimeout(() => {}, 10_000);
      const reconnectSpy = sinon.spy(Connection, "reconnect");

      Connection.handleError(event);

      assert.isNull(Connection.connectionTimer);
      sinon.assert.calledOnce(reconnectSpy);
    });
  });

  describe("handleMessage()", () => {
    it("handles pong message", () => {
      Connection.pongTimer = setTimeout(() => {}, 10_000);

      const event = {data: '"pong"'};
      Connection.handleMessage(event);

      assert.isNull(Connection.pongTimer);
    });

    it("handles reload message", () => {
      const reloadSpy = sinon.spy();

      globalThis.document = {
        location: {
          reload: reloadSpy,
        },
      };

      const event = {data: '"reload"'};
      Connection.handleMessage(event);

      sinon.assert.calledOnce(reloadSpy);
    });

    it("handles reply message with correlation ID", () => {
      const correlationId = "123";
      const onSuccess = sinon.spy();
      const onError = sinon.spy();
      const timerId = setTimeout(() => {}, 10_000);
      const clearTimeoutSpy = sinon.spy(globalThis, "clearTimeout");

      Connection.pendingRequests.set(correlationId, {
        timerId,
        onSuccess,
        onError,
      });

      const message = `["reply","payload","${correlationId}"]`;
      const event = {data: message};

      Connection.handleMessage(event);

      sinon.assert.calledOnce(onSuccess);
      sinon.assert.notCalled(onError);
      sinon.assert.calledOnceWithExactly(clearTimeoutSpy, timerId);
      assert.isFalse(Connection.pendingRequests.has(correlationId));

      clearTimeoutSpy.restore();
    });

    it("ignores reply message with unknown correlation ID", () => {
      const message = '["reply","payload","234"]';
      const event = {data: message};

      // Should not throw
      Connection.handleMessage(event);
    });

    it("handles compilation_error message", () => {
      const showErrorOverlaySpy = sinon.stub(LiveReload, "showErrorOverlay");
      const errorOutput = "Compilation error details";

      const message = `["compilation_error","${errorOutput}"]`;
      const event = {data: message};

      Connection.handleMessage(event);

      sinon.assert.calledOnceWithExactly(showErrorOverlaySpy, errorOutput);

      showErrorOverlaySpy.restore();
    });
  });

  describe("handleOpen()", () => {
    const event = {};
    let consoleLogStub;

    beforeEach(() => {
      consoleLogStub = sinon.stub(console, "log");
    });

    afterEach(() => {
      consoleLogStub.restore();
    });

    it("logs connection, updates status, and sets global registry", () => {
      Connection.handleOpen(event);

      sinon.assert.calledWith(consoleLogStub, "Hologram: connected to server");
      assert.equal(Connection.status, "connected");
      sinon.assert.calledWith(GlobalRegistry.set, "connected?", true);
    });

    it("resets reconnect attempts and clears connection timer", () => {
      Connection.reconnectAttempts = 5;
      Connection.connectionTimer = setTimeout(() => {}, 10_000);

      Connection.handleOpen(event);

      assert.equal(Connection.reconnectAttempts, 0);
      assert.isNull(Connection.connectionTimer);
    });

    it("starts ping mechanism", () => {
      const startPingSpy = sinon.spy(Connection, "startPing");

      Connection.handleOpen(event);

      sinon.assert.calledOnce(startPingSpy);
    });
  });

  describe("isConnected()", () => {
    it("returns true when status is connected", () => {
      Connection.status = "connected";
      assert.isTrue(Connection.isConnected());
    });

    it("returns false when status is not connected", () => {
      Connection.status = "disconnected";
      assert.isFalse(Connection.isConnected());

      Connection.status = "connecting";
      assert.isFalse(Connection.isConnected());

      Connection.status = "error";
      assert.isFalse(Connection.isConnected());
    });
  });

  describe("reconnect()", () => {
    let consoleLogStub;

    beforeEach(() => {
      consoleLogStub = sinon.stub(console, "log");
    });

    afterEach(() => {
      consoleLogStub.restore();
    });

    it("calculates exponential backoff delay", () => {
      Connection.reconnectAttempts = 0;

      Connection.reconnect();

      assert.equal(Connection.reconnectAttempts, 1);

      const expectedDelay = Connection.BASE_RECONNECT_DELAY * Math.pow(2, 0);

      sinon.assert.calledWith(
        consoleLogStub,
        `Hologram: reconnecting in ${expectedDelay} ms (attempt 1)`,
      );
    });

    it("caps delay at MAX_RECONNECT_DELAY", () => {
      // Large number to test cap
      Connection.reconnectAttempts = 10;

      Connection.reconnect();

      sinon.assert.calledWith(
        consoleLogStub,
        `Hologram: reconnecting in ${Connection.MAX_RECONNECT_DELAY} ms (attempt 11)`,
      );
    });

    it("schedules reconnection", () => {
      Connection.reconnect();

      assert.isNotNull(Connection.reconnectTimer);
    });

    it("calls connect after delay", () => {
      const connectSpy = sinon.spy(Connection, "connect");

      Connection.reconnect();
      clock.tick(Connection.BASE_RECONNECT_DELAY);

      sinon.assert.calledOnce(connectSpy);
    });
  });

  describe("sendMessage()", () => {
    let consoleErrorStub;

    beforeEach(() => {
      consoleErrorStub = sinon.stub(console, "error");
    });

    afterEach(() => {
      consoleErrorStub.restore();
    });

    it("sends message when connected", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const result = Connection.sendMessage("test", Type.atom("abc"), "123");

      assert.isTrue(result);
      sinon.assert.calledOnce(mockWebSocket.send);
    });

    it("fails to send when not connected", () => {
      Connection.status = "disconnected";

      const result = Connection.sendMessage("test", null, null);

      assert.isFalse(result);

      sinon.assert.calledWith(
        consoleErrorStub,
        "Hologram: failed to send message to server",
        "test",
        null,
        null,
      );
    });

    it("handles websocket send errors", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;
      mockWebSocket.send = sinon.stub().throws(new Error("Send error"));

      const result = Connection.sendMessage("test");

      assert.isFalse(result);

      sinon.assert.calledWith(
        consoleErrorStub,
        "Hologram: failed to send message to server",
        "test",
        null,
        null,
      );
    });

    it("encodes the message", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;
      const encodeMessageSpy = sinon.spy(Connection, "encodeMessage");

      const type = "test";
      const payload = Type.atom("abc");
      const correlationId = "123";

      Connection.sendMessage(type, payload, correlationId);

      sinon.assert.calledOnceWithExactly(
        encodeMessageSpy,
        type,
        payload,
        correlationId,
      );

      const expectedEncodedMessage = Connection.encodeMessage(
        type,
        payload,
        correlationId,
      );
      sinon.assert.calledOnceWithExactly(
        mockWebSocket.send,
        expectedEncodedMessage,
      );
    });
  });

  describe("sendRequest()", () => {
    let cryptoStub, opts;

    beforeEach(() => {
      cryptoStub = sinon.stub(crypto, "randomUUID").returns("mock-uuid");

      opts = {
        onSuccess: sinon.spy(),
        onError: sinon.spy(),
        onTimeout: sinon.spy(),
      };
    });

    afterEach(() => {
      cryptoStub.restore();
    });

    it("creates pending request and sends message", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const result = Connection.sendRequest("test", Type.atom("abc"), opts);

      assert.instanceOf(result, Promise);
      assert.isTrue(Connection.pendingRequests.has("mock-uuid"));
      sinon.assert.calledOnce(mockWebSocket.send);
    });

    it("calls callbacks and resolves promise on success", async () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const promise = Connection.sendRequest("test", Type.atom("abc"), opts);

      // Simulate successful WebSocket response
      const responsePayload = "test response payload";
      const message = `["reply","${responsePayload}","mock-uuid"]`;
      const event = {data: message};
      Connection.handleMessage(event);

      sinon.assert.calledOnceWithExactly(opts.onSuccess, responsePayload);

      // Test that promise resolves with the response payload
      const result = await promise;
      assert.equal(result, responsePayload);
    });

    it("calls callbacks and rejects promise on send failure", async () => {
      Connection.status = "disconnected";
      const clearTimeoutSpy = sinon.spy(globalThis, "clearTimeout");

      const promise = Connection.sendRequest("test", Type.atom("abc"), opts);

      sinon.assert.calledOnce(opts.onError);
      assert.isFalse(Connection.pendingRequests.has("mock-uuid"));
      sinon.assert.calledOnce(clearTimeoutSpy);

      try {
        await promise;
        assert.fail("Promise should have rejected");
      } catch (error) {
        assert.instanceOf(error, Error);
        assert.equal(error.message, "Failed to send message");
      }
    });

    it("calls callbacks and rejects promise on timeout", async () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const promise = Connection.sendRequest("test", Type.atom("abc"), opts);

      // Should not timeout before default timeout
      clock.tick(Connection.REQUEST_TIMEOUT - 1);
      sinon.assert.notCalled(opts.onTimeout);
      assert.isTrue(Connection.pendingRequests.has("mock-uuid"));

      // Should timeout at default timeout
      clock.tick(1);
      sinon.assert.calledOnce(opts.onTimeout);
      assert.isFalse(Connection.pendingRequests.has("mock-uuid"));

      try {
        await promise;
        assert.fail("Promise should have rejected");
      } catch (error) {
        assert.instanceOf(error, Error);
        assert.equal(error.message, "Request timeout");
      }
    });

    it("works with promise-only (no callbacks) on success", async () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const promise = Connection.sendRequest("test", Type.atom("abc"));

      // Simulate successful WebSocket response
      const responsePayload = "test response payload";
      const message = `["reply","${responsePayload}","mock-uuid"]`;
      const event = {data: message};
      Connection.handleMessage(event);

      // Test that promise resolves with the response payload
      const result = await promise;
      assert.equal(result, responsePayload);
    });

    it("works with promise-only (no callbacks) on error", async () => {
      Connection.status = "disconnected";

      const promise = Connection.sendRequest("test", Type.atom("abc"));

      try {
        await promise;
        assert.fail("Promise should have rejected");
      } catch (error) {
        assert.instanceOf(error, Error);
        assert.equal(error.message, "Failed to send message");
      }
    });

    it("works with promise-only (no callbacks) on timeout", async () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const promise = Connection.sendRequest("test", Type.atom("abc"));

      // Should not timeout before default timeout
      clock.tick(Connection.REQUEST_TIMEOUT - 1);
      assert.isTrue(Connection.pendingRequests.has("mock-uuid"));

      // Should timeout at default timeout
      clock.tick(1);
      assert.isFalse(Connection.pendingRequests.has("mock-uuid"));

      try {
        await promise;
        assert.fail("Promise should have rejected");
      } catch (error) {
        assert.instanceOf(error, Error);
        assert.equal(error.message, "Request timeout");
      }
    });

    it("uses custom timeout value", async () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      const customTimeout = 5_000;
      opts.timeout = customTimeout;

      const promise = Connection.sendRequest("test", Type.atom("abc"), opts);

      // Should not timeout before custom timeout
      clock.tick(customTimeout - 1);
      sinon.assert.notCalled(opts.onTimeout);
      assert.isTrue(Connection.pendingRequests.has("mock-uuid"));

      // Should timeout at custom timeout
      clock.tick(1);
      sinon.assert.calledOnce(opts.onTimeout);
      assert.isFalse(Connection.pendingRequests.has("mock-uuid"));

      try {
        await promise;
        assert.fail("Promise should have rejected");
      } catch (error) {
        assert.instanceOf(error, Error);
        assert.equal(error.message, "Request timeout");
      }
    });
  });

  describe("sendPing()", () => {
    it("sends ping when connected", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;
      const sendMessageSpy = sinon.spy(Connection, "sendMessage");

      Connection.sendPing();

      sinon.assert.calledOnceWithExactly(sendMessageSpy, "ping");
      assert.isNotNull(Connection.pongTimer);
    });

    it("closes websocket on pong timeout", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;

      let consoleWarnStub = sinon.stub(console, "warn");

      Connection.sendPing();
      clock.tick(Connection.PONG_TIMEOUT);

      sinon.assert.calledWith(consoleWarnStub, "Hologram: pong timeout");
      sinon.assert.calledOnce(mockWebSocket.close);

      consoleWarnStub.restore();
    });

    it("does nothing when not connected", () => {
      Connection.status = "disconnected";
      const sendMessageSpy = sinon.spy(Connection, "sendMessage");

      Connection.sendPing();

      sinon.assert.notCalled(sendMessageSpy);
    });
  });

  describe("startPing()", () => {
    it("clears existing ping timer and starts new one", () => {
      const existingTimer = setInterval(() => {}, 10_000);
      Connection.pingTimer = existingTimer;

      const clearIntervalSpy = sinon.spy(globalThis, "clearInterval");

      Connection.startPing();

      sinon.assert.calledOnceWithExactly(clearIntervalSpy, existingTimer);
      assert.isNotNull(Connection.pingTimer);
      assert.notEqual(Connection.pingTimer, existingTimer);

      clearIntervalSpy.restore();
    });

    it("sends ping at regular intervals when connected", () => {
      Connection.status = "connected";
      Connection.websocket = mockWebSocket;
      const sendPingSpy = sinon.spy(Connection, "sendPing");

      Connection.startPing();

      clock.tick(Connection.PING_INTERVAL);
      sinon.assert.calledOnce(sendPingSpy);

      clock.tick(Connection.PING_INTERVAL);
      sinon.assert.calledTwice(sendPingSpy);
    });

    it("does not send ping when not connected", () => {
      Connection.status = "disconnected";
      const sendPingSpy = sinon.spy(Connection, "sendPing");

      Connection.startPing();
      clock.tick(Connection.PING_INTERVAL);

      sinon.assert.notCalled(sendPingSpy);
    });
  });
});

"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import HttpTransport from "../../assets/js/http_transport.mjs";

defineGlobalErlangAndElixirModules();

describe("HttpTransport", () => {
  let clock;

  let consoleDebugStub;
  let fetchStub;

  beforeEach(() => {
    clock = sinon.useFakeTimers();

    consoleDebugStub = sinon.stub(console, "debug");
    fetchStub = sinon.stub(global, "fetch").resolves();

    HttpTransport.pingTimer = null;
  });

  afterEach(() => {
    HttpTransport.maybeStopPing();

    clock.restore();
    sinon.restore();
  });

  describe("isRunning()", () => {
    it("should return false when pingTimer is null", () => {
      HttpTransport.pingTimer = null;
      assert.isFalse(HttpTransport.isRunning());
    });

    it("should return true when pingTimer is set", () => {
      HttpTransport.startPing();
      assert.isTrue(HttpTransport.isRunning());
    });
  });

  describe("maybeStopPing()", () => {
    it("should do nothing when not running", () => {
      HttpTransport.pingTimer = null;
      HttpTransport.maybeStopPing();

      assert.isFalse(HttpTransport.isRunning());
    });

    it("should clear interval and reset timer when running", () => {
      HttpTransport.startPing();

      HttpTransport.maybeStopPing();

      assert.isFalse(HttpTransport.isRunning());
    });
  });

  describe("ping()", () => {
    it("should make fetch request with correct parameters", () => {
      HttpTransport.ping();

      sinon.assert.calledWith(fetchStub, "/hologram/ping", {
        method: "HEAD",
        keepalive: true,
      });
    });

    it("should handle fetch errors silently", async () => {
      const error = new Error("Network error");
      fetchStub.rejects(error);

      await HttpTransport.ping();

      sinon.assert.calledWith(consoleDebugStub, "Ping request failed:", error);
    });
  });

  describe("restartPing()", () => {
    it("should stop existing ping and start new one", () => {
      // Start initial ping
      HttpTransport.startPing();
      sinon.assert.calledOnce(fetchStub);

      // Let some time pass
      clock.tick(15_000); // Half interval
      sinon.assert.calledOnce(fetchStub); // Still only initial ping

      // Restart ping
      HttpTransport.restartPing();
      sinon.assert.calledTwice(fetchStub); // New immediate ping

      // The interval should reset - wait full interval
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledThrice(fetchStub);
    });

    it("should maintain running state during restart", () => {
      HttpTransport.startPing();
      assert.isTrue(HttpTransport.isRunning());

      HttpTransport.restartPing();
      assert.isTrue(HttpTransport.isRunning());
    });
  });

  describe("startPing()", () => {
    it("should call ping immediately", () => {
      HttpTransport.startPing();

      sinon.assert.calledOnce(fetchStub);
    });

    it("should set timer and mark as running", () => {
      HttpTransport.startPing();

      assert.isTrue(HttpTransport.isRunning());
    });

    it("should call ping at regular intervals", () => {
      HttpTransport.startPing();

      // Initial ping
      sinon.assert.calledOnce(fetchStub);

      // First interval
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledTwice(fetchStub);

      // Second interval
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledThrice(fetchStub);

      // Third interval
      clock.tick(HttpTransport.PING_INTERVAL);
      assert.equal(fetchStub.callCount, 4);
    });

    it("should not call ping before interval elapses", () => {
      HttpTransport.startPing();

      // Initial ping
      sinon.assert.calledOnce(fetchStub);

      // Just before the interval
      clock.tick(HttpTransport.PING_INTERVAL - 1);
      sinon.assert.calledOnce(fetchStub);

      // Complete the interval
      clock.tick(1);
      sinon.assert.calledTwice(fetchStub);
    });
  });

  describe("integration", () => {
    it("should handle complete ping lifecycle with timing", () => {
      // Start ping
      HttpTransport.startPing();
      assert.isTrue(HttpTransport.isRunning());
      sinon.assert.calledOnce(fetchStub);

      // Verify pings happen at correct intervals
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledTwice(fetchStub);

      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledThrice(fetchStub);

      // Stop ping
      HttpTransport.maybeStopPing();
      assert.isFalse(HttpTransport.isRunning());

      // Verify no more pings after stopping
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledThrice(fetchStub); // No additional calls
    });

    it("should handle restart without timing disruption", () => {
      // Start initial ping
      HttpTransport.startPing();
      sinon.assert.calledOnce(fetchStub);

      // Wait partial interval
      clock.tick(10_000);
      sinon.assert.calledOnce(fetchStub);

      // Restart - should immediately ping and reset timer
      HttpTransport.restartPing();
      sinon.assert.calledTwice(fetchStub);

      // New interval should start from restart point
      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledThrice(fetchStub);

      // Continue with regular intervals
      clock.tick(HttpTransport.PING_INTERVAL);
      assert.equal(fetchStub.callCount, 4);
    });

    it("should handle multiple stop/start cycles", () => {
      // First cycle
      HttpTransport.startPing();
      sinon.assert.calledOnce(fetchStub);

      clock.tick(HttpTransport.PING_INTERVAL);
      sinon.assert.calledTwice(fetchStub);

      HttpTransport.maybeStopPing();

      // Wait while stopped - no pings
      clock.tick(HttpTransport.PING_INTERVAL * 2);
      sinon.assert.calledTwice(fetchStub);

      // Second cycle
      HttpTransport.startPing();
      sinon.assert.calledThrice(fetchStub);

      clock.tick(HttpTransport.PING_INTERVAL);
      assert.equal(fetchStub.callCount, 4);
    });
  });
});

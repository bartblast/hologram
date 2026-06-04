"use strict";

import {sinon} from "./support/helpers.mjs";

import Throttler from "../../assets/js/throttler.mjs";

describe("Throttler", () => {
  let clock;

  beforeEach(() => {
    clock = sinon.useFakeTimers();
  });

  afterEach(() => {
    clock.restore();
  });

  describe("run()", () => {
    it("dispatches the first call immediately on the leading edge", () => {
      const callback = sinon.spy();

      Throttler.run({}, "slot", 100, callback);

      sinon.assert.calledOnce(callback);
    });

    it("holds calls during the window and fires the latest on the trailing edge", () => {
      const element = {};
      const leading = sinon.spy();
      const middle = sinon.spy();
      const trailing = sinon.spy();

      Throttler.run(element, "slot", 100, leading);
      Throttler.run(element, "slot", 100, middle);
      Throttler.run(element, "slot", 100, trailing);

      // Only the leading call has fired so far.
      sinon.assert.calledOnce(leading);
      sinon.assert.notCalled(middle);
      sinon.assert.notCalled(trailing);

      clock.tick(100);

      // Trailing edge: only the latest held call fires.
      sinon.assert.notCalled(middle);
      sinon.assert.calledOnce(trailing);
    });

    it("does not fire a trailing call when nothing arrives during the window", () => {
      const callback = sinon.spy();

      Throttler.run({}, "slot", 100, callback);
      clock.tick(100);

      // Leading only - no trailing dispatch.
      sinon.assert.calledOnce(callback);
    });

    it("dispatches at most once per window while calls keep arriving", () => {
      const element = {};
      const callback = sinon.spy();

      Throttler.run(element, "slot", 100, callback);

      // Keep calling across two full windows (10 * 20ms = 200ms).
      for (let i = 0; i < 10; i++) {
        Throttler.run(element, "slot", 100, callback);
        clock.tick(20);
      }

      // Leading plus one trailing per 100ms window.
      sinon.assert.calledThrice(callback);
    });

    it("starts a fresh leading edge after the window closes idle", () => {
      const element = {};
      const callback = sinon.spy();

      Throttler.run(element, "slot", 100, callback);
      clock.tick(100); // window closes with nothing pending
      sinon.assert.calledOnce(callback);

      Throttler.run(element, "slot", 100, callback);
      sinon.assert.calledTwice(callback);
    });

    it("keeps an independent window per slot on the same element", () => {
      const element = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Throttler.run(element, "slot-a", 100, callbackA);
      Throttler.run(element, "slot-b", 100, callbackB);
      Throttler.run(element, "slot-a", 100, callbackA);
      Throttler.run(element, "slot-b", 100, callbackB);

      // Each slot fired its own leading call; the held calls wait.
      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);

      clock.tick(100);

      // Each slot fires its own trailing call independently.
      sinon.assert.calledTwice(callbackA);
      sinon.assert.calledTwice(callbackB);
    });

    it("keeps an independent window per element for the same slot", () => {
      const elementA = {};
      const elementB = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Throttler.run(elementA, "slot", 100, callbackA);
      Throttler.run(elementB, "slot", 100, callbackB);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);
    });
  });
});

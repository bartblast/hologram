"use strict";

import {sinon} from "./support/helpers.mjs";

import Debouncer from "../../assets/js/debouncer.mjs";

describe("Debouncer", () => {
  let clock;

  beforeEach(() => {
    clock = sinon.useFakeTimers();
  });

  afterEach(() => {
    clock.restore();
  });

  describe("flush()", () => {
    it("fires the pending callback immediately", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      Debouncer.flush(element);

      sinon.assert.calledOnce(callback);
    });

    it("does not fire the callback again when the flushed timer's delay elapses", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      Debouncer.flush(element);
      clock.tick(250);

      sinon.assert.calledOnce(callback);
    });

    it("fires every pending slot on the element in scheduling order", () => {
      const element = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(element, "slot-a", 250, callbackA);
      Debouncer.run(element, "slot-b", 250, callbackB);
      Debouncer.flush(element);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);
      sinon.assert.callOrder(callbackA, callbackB);
    });

    it("leaves pending entries of other elements untouched", () => {
      const elementA = {};
      const elementB = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(elementA, "slot", 250, callbackA);
      Debouncer.run(elementB, "slot", 250, callbackB);
      Debouncer.flush(elementA);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.notCalled(callbackB);

      // The untouched element's timer still fires on its own schedule.
      clock.tick(250);
      sinon.assert.calledOnce(callbackB);
    });

    it("is a no-op for an element with nothing pending", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.flush(element);

      sinon.assert.notCalled(callback);
    });

    it("a flushed slot can be scheduled again", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      Debouncer.flush(element);
      sinon.assert.calledOnce(callback);

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(250);
      sinon.assert.calledTwice(callback);
    });
  });

  describe("flushWithin()", () => {
    // Minimal stand-in for a DOM container: contains() covers itself and the given descendants.
    const buildContainer = (...descendants) => ({
      nodeType: 1,
      contains(node) {
        return node === this || descendants.includes(node);
      },
    });

    const buildElement = () => ({nodeType: 1});

    it("fires pending entries on the container's descendants in scheduling order", () => {
      const elementA = buildElement();
      const elementB = buildElement();
      const container = buildContainer(elementA, elementB);
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(elementA, "slot", 250, callbackA);
      Debouncer.run(elementB, "slot", 250, callbackB);
      Debouncer.flushWithin(container);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);
      sinon.assert.callOrder(callbackA, callbackB);
    });

    it("fires pending entries keyed on the container itself", () => {
      const container = buildContainer();
      const callback = sinon.spy();

      Debouncer.run(container, "slot", 250, callback);
      Debouncer.flushWithin(container);

      sinon.assert.calledOnce(callback);
    });

    it("leaves elements outside the container untouched", () => {
      const inside = buildElement();
      const outside = buildElement();
      const container = buildContainer(inside);
      const insideCallback = sinon.spy();
      const outsideCallback = sinon.spy();

      Debouncer.run(inside, "slot", 250, insideCallback);
      Debouncer.run(outside, "slot", 250, outsideCallback);
      Debouncer.flushWithin(container);

      sinon.assert.calledOnce(insideCallback);
      sinon.assert.notCalled(outsideCallback);

      // The untouched element's timer still fires on its own schedule.
      clock.tick(250);
      sinon.assert.calledOnce(outsideCallback);
    });

    it("skips entries keyed on non-node targets", () => {
      const windowTarget = {};
      const container = buildContainer(windowTarget);
      const callback = sinon.spy();

      Debouncer.run(windowTarget, "slot", 250, callback);
      Debouncer.flushWithin(container);

      sinon.assert.notCalled(callback);

      // The skipped entry's timer still fires on its own schedule.
      clock.tick(250);
      sinon.assert.calledOnce(callback);
    });
  });

  describe("run()", () => {
    it("does not call the callback before the delay elapses", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(249);

      sinon.assert.notCalled(callback);
    });

    it("calls the callback once after the delay elapses", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(250);

      sinon.assert.calledOnce(callback);
    });

    it("a repeated run within the window restarts the timer, so only the last call fires", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(200);
      Debouncer.run(element, "slot", 250, callback);
      clock.tick(200);

      // 400ms have elapsed, but the second run reset the window at 200ms, so nothing fired yet.
      sinon.assert.notCalled(callback);

      clock.tick(50);
      sinon.assert.calledOnce(callback);
    });

    it("keeps an independent timer per slot on the same element", () => {
      const element = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(element, "slot-a", 250, callbackA);
      Debouncer.run(element, "slot-b", 250, callbackB);
      clock.tick(250);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);
    });

    it("does not let one slot cancel another on the same element", () => {
      const element = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(element, "slot-a", 250, callbackA);
      clock.tick(100);
      Debouncer.run(element, "slot-b", 250, callbackB);

      // slot-a reaches 250ms and fires; slot-b is only 150ms in.
      clock.tick(150);
      sinon.assert.calledOnce(callbackA);
      sinon.assert.notCalled(callbackB);

      // slot-b reaches 250ms and fires.
      clock.tick(100);
      sinon.assert.calledOnce(callbackB);
    });

    it("keeps an independent timer per element for the same slot", () => {
      const elementA = {};
      const elementB = {};
      const callbackA = sinon.spy();
      const callbackB = sinon.spy();

      Debouncer.run(elementA, "slot", 250, callbackA);
      Debouncer.run(elementB, "slot", 250, callbackB);
      clock.tick(250);

      sinon.assert.calledOnce(callbackA);
      sinon.assert.calledOnce(callbackB);
    });

    it("schedules again after a completed run", () => {
      const element = {};
      const callback = sinon.spy();

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(250);
      sinon.assert.calledOnce(callback);

      Debouncer.run(element, "slot", 250, callback);
      clock.tick(250);
      sinon.assert.calledTwice(callback);
    });
  });
});

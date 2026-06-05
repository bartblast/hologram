"use strict";

import {sinon} from "./support/helpers.mjs";

import WindowEventRegistry from "../../assets/js/window_event_registry.mjs";

describe("WindowEventRegistry", () => {
  let addSpy;
  let removeSpy;

  beforeEach(() => {
    addSpy = sinon.spy(window, "addEventListener");
    removeSpy = sinon.spy(window, "removeEventListener");
  });

  afterEach(() => {
    // Tear down any listeners installed by the test, then restore the spies.
    WindowEventRegistry.reconcile([]);
    sinon.restore();
  });

  describe("reconcile()", () => {
    it("installs one real listener when an event first gains a binding", () => {
      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: sinon.spy()},
      ]);

      sinon.assert.calledOnceWithExactly(addSpy, "keydown", sinon.match.func);
    });

    it("installs a single listener for multiple bindings of the same event", () => {
      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: sinon.spy()},
        {eventName: "keydown", handler: sinon.spy()},
      ]);

      sinon.assert.calledOnce(addSpy);
    });

    it("fans a dispatched event out to every binding for that event", () => {
      const handler1 = sinon.spy();
      const handler2 = sinon.spy();

      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: handler1},
        {eventName: "keydown", handler: handler2},
      ]);

      const event = new window.Event("keydown");
      window.dispatchEvent(event);

      sinon.assert.calledOnceWithExactly(handler1, event);
      sinon.assert.calledOnceWithExactly(handler2, event);
    });

    it("refreshes handlers without re-adding the listener", () => {
      const oldHandler = sinon.spy();
      const newHandler = sinon.spy();

      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: oldHandler},
      ]);

      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: newHandler},
      ]);

      // The real listener was added once and never re-added across the two renders.
      sinon.assert.calledOnce(addSpy);
      sinon.assert.notCalled(removeSpy);

      window.dispatchEvent(new window.Event("keydown"));

      // Only the latest render's handler runs.
      sinon.assert.notCalled(oldHandler);
      sinon.assert.calledOnce(newHandler);
    });

    it("removes the real listener when the last binding for an event goes away", () => {
      const handler = sinon.spy();

      WindowEventRegistry.reconcile([{eventName: "keydown", handler}]);
      WindowEventRegistry.reconcile([]);

      sinon.assert.calledOnceWithExactly(
        removeSpy,
        "keydown",
        sinon.match.func,
      );

      window.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(handler);
    });

    it("removes only the dropped event and keeps the others", () => {
      const keydownHandler = sinon.spy();
      const keyupHandler = sinon.spy();

      WindowEventRegistry.reconcile([
        {eventName: "keydown", handler: keydownHandler},
        {eventName: "keyup", handler: keyupHandler},
      ]);

      WindowEventRegistry.reconcile([
        {eventName: "keyup", handler: keyupHandler},
      ]);

      sinon.assert.calledOnceWithExactly(
        removeSpy,
        "keydown",
        sinon.match.func,
      );

      window.dispatchEvent(new window.Event("keydown"));
      window.dispatchEvent(new window.Event("keyup"));

      sinon.assert.notCalled(keydownHandler);
      sinon.assert.calledOnce(keyupHandler);
    });
  });
});

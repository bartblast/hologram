"use strict";

import {sinon} from "./support/helpers.mjs";

import GlobalEventRegistry from "../../assets/js/global_event_registry.mjs";

describe("GlobalEventRegistry", () => {
  let windowAddSpy;
  let windowRemoveSpy;
  let documentAddSpy;
  let documentRemoveSpy;

  beforeEach(() => {
    windowAddSpy = sinon.spy(window, "addEventListener");
    windowRemoveSpy = sinon.spy(window, "removeEventListener");
    documentAddSpy = sinon.spy(document, "addEventListener");
    documentRemoveSpy = sinon.spy(document, "removeEventListener");
  });

  afterEach(() => {
    // Tear down any listeners installed by the test, then restore the spies.
    GlobalEventRegistry.reconcile([]);
    sinon.restore();
  });

  describe("reconcile()", () => {
    it("installs one real listener when an event first gains a binding on a target", () => {
      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: sinon.spy()},
      ]);

      sinon.assert.calledOnceWithExactly(
        windowAddSpy,
        "keydown",
        sinon.match.func,
      );
    });

    it("installs a single listener for multiple bindings of the same target and event", () => {
      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: sinon.spy()},
        {target: window, eventName: "keydown", handler: sinon.spy()},
      ]);

      sinon.assert.calledOnce(windowAddSpy);
    });

    it("fans a dispatched event out to every binding for that target and event", () => {
      const handler1 = sinon.spy();
      const handler2 = sinon.spy();

      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: handler1},
        {target: window, eventName: "keydown", handler: handler2},
      ]);

      const event = new window.Event("keydown");
      window.dispatchEvent(event);

      sinon.assert.calledOnceWithExactly(handler1, event);
      sinon.assert.calledOnceWithExactly(handler2, event);
    });

    it("refreshes handlers without re-adding the listener", () => {
      const oldHandler = sinon.spy();
      const newHandler = sinon.spy();

      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: oldHandler},
      ]);

      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: newHandler},
      ]);

      sinon.assert.calledOnce(windowAddSpy);
      sinon.assert.notCalled(windowRemoveSpy);

      window.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(oldHandler);
      sinon.assert.calledOnce(newHandler);
    });

    it("removes the real listener when the last binding for an event goes away", () => {
      const handler = sinon.spy();

      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler},
      ]);

      GlobalEventRegistry.reconcile([]);

      sinon.assert.calledOnceWithExactly(
        windowRemoveSpy,
        "keydown",
        sinon.match.func,
      );

      window.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(handler);
    });

    it("reconciles targets independently", () => {
      const windowHandler = sinon.spy();
      const documentHandler = sinon.spy();

      GlobalEventRegistry.reconcile([
        {target: window, eventName: "keydown", handler: windowHandler},
        {target: document, eventName: "keydown", handler: documentHandler},
      ]);

      // Each target gets its own real listener.
      sinon.assert.calledOnceWithExactly(
        windowAddSpy,
        "keydown",
        sinon.match.func,
      );

      sinon.assert.calledOnceWithExactly(
        documentAddSpy,
        "keydown",
        sinon.match.func,
      );

      // Dropping the window binding removes only the window listener; the document one stays.
      GlobalEventRegistry.reconcile([
        {target: document, eventName: "keydown", handler: documentHandler},
      ]);

      sinon.assert.calledOnceWithExactly(
        windowRemoveSpy,
        "keydown",
        sinon.match.func,
      );

      sinon.assert.notCalled(documentRemoveSpy);

      window.dispatchEvent(new window.Event("keydown"));
      document.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(windowHandler);
      sinon.assert.calledOnce(documentHandler);
    });
  });
});

"use strict";

import {sinon} from "./support/helpers.mjs";

import EventListenerRegistry from "../../assets/js/event_listener_registry.mjs";
import EventListeners from "../../assets/js/event_listeners.mjs";

describe("EventListenerRegistry", () => {
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
    EventListenerRegistry.reconcile([]);
    sinon.restore();
  });

  describe("reconcile()", () => {
    it("installs one real listener when an event first gains a binding on a target", () => {
      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: sinon.spy(),
        },
      ]);

      sinon.assert.calledOnceWithExactly(
        windowAddSpy,
        "keydown",
        sinon.match.func,
        false,
      );
    });

    it("installs a single listener for multiple bindings of the same target and event", () => {
      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: sinon.spy(),
        },
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: sinon.spy(),
        },
      ]);

      sinon.assert.calledOnce(windowAddSpy);
    });

    it("fans a dispatched event out to every binding for that target and event", () => {
      const handler1 = sinon.spy();
      const handler2 = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: handler1,
        },
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: handler2,
        },
      ]);

      const event = new window.Event("keydown");
      window.dispatchEvent(event);

      sinon.assert.calledOnceWithExactly(handler1, event);
      sinon.assert.calledOnceWithExactly(handler2, event);
    });

    it("refreshes handlers without re-adding the listener", () => {
      const oldHandler = sinon.spy();
      const newHandler = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: oldHandler,
        },
      ]);

      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: newHandler,
        },
      ]);

      sinon.assert.calledOnce(windowAddSpy);
      sinon.assert.notCalled(windowRemoveSpy);

      window.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(oldHandler);
      sinon.assert.calledOnce(newHandler);
    });

    it("removes the real listener when the last binding for an event goes away", () => {
      const handler = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler,
        },
      ]);

      EventListenerRegistry.reconcile([]);

      sinon.assert.calledOnceWithExactly(
        windowRemoveSpy,
        "keydown",
        sinon.match.func,
        false,
      );

      window.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(handler);
    });

    it("reconciles targets independently", () => {
      const windowHandler = sinon.spy();
      const documentHandler = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: windowHandler,
        },
        {
          target: document,
          ...EventListeners.domEvent(document, "keydown"),
          handler: documentHandler,
        },
      ]);

      // Each target gets its own real listener.
      sinon.assert.calledOnceWithExactly(
        windowAddSpy,
        "keydown",
        sinon.match.func,
        false,
      );

      sinon.assert.calledOnceWithExactly(
        documentAddSpy,
        "keydown",
        sinon.match.func,
        false,
      );

      // Dropping the window binding removes only the window listener; the document one stays.
      EventListenerRegistry.reconcile([
        {
          target: document,
          ...EventListeners.domEvent(document, "keydown"),
          handler: documentHandler,
        },
      ]);

      sinon.assert.calledOnceWithExactly(
        windowRemoveSpy,
        "keydown",
        sinon.match.func,
        false,
      );

      sinon.assert.notCalled(documentRemoveSpy);

      window.dispatchEvent(new window.Event("keydown"));
      document.dispatchEvent(new window.Event("keydown"));

      sinon.assert.notCalled(windowHandler);
      sinon.assert.calledOnce(documentHandler);
    });

    it("installs a capture-phase listener when a binding sets capture", () => {
      EventListenerRegistry.reconcile([
        {
          target: document,
          ...EventListeners.domEvent(document, "click", true),
          handler: sinon.spy(),
        },
      ]);

      sinon.assert.calledOnceWithExactly(
        documentAddSpy,
        "click",
        sinon.match.func,
        true,
      );
    });

    it("keeps capture and bubble listeners for the same target and event separate", () => {
      const bubbleHandler = sinon.spy();
      const captureHandler = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: document,
          ...EventListeners.domEvent(document, "click"),
          handler: bubbleHandler,
        },
        {
          target: document,
          ...EventListeners.domEvent(document, "click", true),
          handler: captureHandler,
        },
      ]);

      // Two distinct real listeners - one per phase.
      sinon.assert.calledTwice(documentAddSpy);

      sinon.assert.calledWithExactly(
        documentAddSpy,
        "click",
        sinon.match.func,
        false,
      );

      sinon.assert.calledWithExactly(
        documentAddSpy,
        "click",
        sinon.match.func,
        true,
      );

      // Dropping the bubble binding removes only the bubble listener; the capture one stays.
      EventListenerRegistry.reconcile([
        {
          target: document,
          ...EventListeners.domEvent(document, "click", true),
          handler: captureHandler,
        },
      ]);

      sinon.assert.calledOnceWithExactly(
        documentRemoveSpy,
        "click",
        sinon.match.func,
        false,
      );
    });
  });
});

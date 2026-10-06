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
    EventListenerRegistry.detachAll();
    sinon.restore();
  });

  describe("detachAll()", () => {
    it("detaches every live listener on every target", () => {
      EventListenerRegistry.reconcile([
        {
          target: window,
          ...EventListeners.domEvent(window, "keydown"),
          handler: sinon.spy(),
        },
        {
          target: document,
          ...EventListeners.domEvent(document, "click", true),
          handler: sinon.spy(),
        },
      ]);

      EventListenerRegistry.detachAll();

      sinon.assert.calledOnceWithExactly(
        windowRemoveSpy,
        "keydown",
        sinon.match.func,
        false,
      );

      sinon.assert.calledOnceWithExactly(
        documentRemoveSpy,
        "click",
        sinon.match.func,
        true,
      );
    });

    it("is a no-op when nothing is live", () => {
      EventListenerRegistry.detachAll();

      sinon.assert.notCalled(windowRemoveSpy);
      sinon.assert.notCalled(documentRemoveSpy);
    });

    it("leaves the registry empty, so a later reconcile attaches afresh", () => {
      const binding = {
        target: window,
        ...EventListeners.domEvent(window, "keydown"),
        handler: sinon.spy(),
      };

      EventListenerRegistry.reconcile([binding]);
      EventListenerRegistry.detachAll();
      EventListenerRegistry.reconcile([binding]);

      sinon.assert.calledTwice(windowAddSpy);
    });

    // An observer binding has no removeEventListener to spy on: its teardown is whatever its
    // attach returned, so that is what must run.
    it("runs each entry's own detach", () => {
      const detachSpy = sinon.spy();

      EventListenerRegistry.reconcile([
        {
          target: {},
          key: "observer",
          attach: () => detachSpy,
          handler: sinon.spy(),
        },
      ]);

      EventListenerRegistry.detachAll();

      sinon.assert.calledOnce(detachSpy);
    });
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

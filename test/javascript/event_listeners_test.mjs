"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import EventListeners from "../../assets/js/event_listeners.mjs";

describe("EventListeners", () => {
  describe("domEvent()", () => {
    it("attaches and detaches a DOM event listener on the target", () => {
      const target = {
        addEventListener: sinon.spy(),
        removeEventListener: sinon.spy(),
      };

      const dispatcher = sinon.spy();
      const detach = EventListeners.domEvent(target, "click", true).attach(
        dispatcher,
      );

      sinon.assert.calledOnceWithExactly(
        target.addEventListener,
        "click",
        dispatcher,
        true,
      );

      detach();

      sinon.assert.calledOnceWithExactly(
        target.removeEventListener,
        "click",
        dispatcher,
        true,
      );
    });

    it("defaults to the bubble phase", () => {
      const target = {
        addEventListener: sinon.spy(),
        removeEventListener: sinon.spy(),
      };

      EventListeners.domEvent(target, "click").attach(sinon.spy());

      sinon.assert.calledOnceWithExactly(
        target.addEventListener,
        "click",
        sinon.match.func,
        false,
      );
    });

    it("keys a bubble-phase listener distinctly from a capture-phase one", () => {
      assert.notEqual(
        EventListeners.domEvent(window, "click").key,
        EventListeners.domEvent(window, "click", true).key,
      );
    });
  });

  describe("resizeObserver()", () => {
    let observers;
    let originalResizeObserver;

    beforeEach(() => {
      observers = [];
      originalResizeObserver = globalThis.ResizeObserver;

      globalThis.ResizeObserver = class {
        constructor(callback) {
          this.callback = callback;
          this.observe = sinon.spy();
          this.disconnect = sinon.spy();
          observers.push(this);
        }
      };
    });

    afterEach(() => {
      globalThis.ResizeObserver = originalResizeObserver;
    });

    it("observes the element and disconnects on detach", () => {
      const element = {};

      const detach = EventListeners.resizeObserver(element).attach(sinon.spy());
      const observer = observers[0];

      sinon.assert.calledOnceWithExactly(observer.observe, element);

      detach();

      sinon.assert.calledOnce(observer.disconnect);
    });

    it("suppresses the initial fire and dispatches the entry on later changes", () => {
      const dispatcher = sinon.spy();

      EventListeners.resizeObserver({}).attach(dispatcher);
      const observer = observers[0];
      const entry = {borderBoxSize: [{blockSize: 10, inlineSize: 20}]};

      observer.callback([entry]);
      sinon.assert.notCalled(dispatcher);

      observer.callback([entry]);
      sinon.assert.calledOnceWithExactly(dispatcher, entry);
    });
  });
});

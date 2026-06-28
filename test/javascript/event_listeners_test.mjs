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

  describe("intersectionObserver()", () => {
    let observers;
    let originalIntersectionObserver;

    beforeEach(() => {
      observers = [];
      originalIntersectionObserver = globalThis.IntersectionObserver;

      globalThis.IntersectionObserver = class {
        constructor(callback, options) {
          this.callback = callback;
          this.options = options;
          this.observe = sinon.spy();
          this.disconnect = sinon.spy();
          observers.push(this);
        }
      };
    });

    afterEach(() => {
      globalThis.IntersectionObserver = originalIntersectionObserver;
    });

    it("observes the element within its parent as root and disconnects on detach", () => {
      const parent = {};
      const element = {parentElement: parent};

      const detach = EventListeners.intersectionObserver(
        element,
        "bottom",
      ).attach(sinon.spy());

      const observer = observers[0];

      assert.strictEqual(observer.options.root, parent);
      sinon.assert.calledOnceWithExactly(observer.observe, element);

      detach();

      sinon.assert.calledOnce(observer.disconnect);
    });

    it("keeps the initial fire and dispatches the entry on every change", () => {
      const dispatcher = sinon.spy();

      EventListeners.intersectionObserver({parentElement: {}}, "bottom").attach(
        dispatcher,
      );

      const observer = observers[0];
      const entry = {isIntersecting: true};

      observer.callback([entry]);
      sinon.assert.calledOnceWithExactly(dispatcher, entry);
    });

    it("keys each edge distinctly", () => {
      const element = {parentElement: {}};

      const keys = ["bottom", "left", "right", "top"].map(
        (edge) => EventListeners.intersectionObserver(element, edge).key,
      );

      assert.strictEqual(new Set(keys).size, 4);
    });

    it("defaults the rootMargin to one viewport past the binding's edge", () => {
      const element = {parentElement: {}};

      const rootMargin = (edge) => {
        EventListeners.intersectionObserver(element, edge).attach(sinon.spy());
        return observers[observers.length - 1].options.rootMargin;
      };

      assert.strictEqual(rootMargin("top"), "100% 0px 0px 0px");
      assert.strictEqual(rootMargin("right"), "0px 100% 0px 0px");
      assert.strictEqual(rootMargin("bottom"), "0px 0px 100% 0px");
      assert.strictEqual(rootMargin("left"), "0px 0px 0px 100%");
    });

    it("overrides the default rootMargin with a given margin on the binding's edge", () => {
      const element = {parentElement: {}};

      EventListeners.intersectionObserver(element, "bottom", "200px").attach(
        sinon.spy(),
      );

      assert.strictEqual(observers[0].options.rootMargin, "0px 0px 200px 0px");
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

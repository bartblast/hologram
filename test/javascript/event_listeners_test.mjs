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

  describe("scrollEdge()", () => {
    let originalRaf;
    let originalCaf;
    let originalResizeObserver;
    let rafCallbacks;
    let resizeObservers;

    const mockElement = (metrics = {}) => ({
      addEventListener: sinon.spy(),
      removeEventListener: sinon.spy(),
      children: [],
      clientHeight: 0,
      clientWidth: 0,
      scrollHeight: 0,
      scrollLeft: 0,
      scrollTop: 0,
      scrollWidth: 0,
      ...metrics,
    });

    const flushFrames = () => {
      const callbacks = rafCallbacks;
      rafCallbacks = [];
      callbacks.forEach((callback) => callback());
    };

    beforeEach(() => {
      rafCallbacks = [];
      resizeObservers = [];
      originalRaf = globalThis.requestAnimationFrame;
      originalCaf = globalThis.cancelAnimationFrame;
      originalResizeObserver = globalThis.ResizeObserver;

      globalThis.requestAnimationFrame = (callback) => {
        rafCallbacks.push(callback);
        return rafCallbacks.length;
      };

      globalThis.cancelAnimationFrame = sinon.spy();

      globalThis.ResizeObserver = class {
        constructor(callback) {
          this.callback = callback;
          this.observe = sinon.spy();
          this.unobserve = sinon.spy();
          this.disconnect = sinon.spy();
          resizeObservers.push(this);
        }
      };
    });

    afterEach(() => {
      globalThis.requestAnimationFrame = originalRaf;
      globalThis.cancelAnimationFrame = originalCaf;
      globalThis.ResizeObserver = originalResizeObserver;
    });

    it("attaches a passive scroll listener and removes it on detach", () => {
      const element = mockElement();

      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        sinon.spy(),
      );

      const onScroll = element.addEventListener.firstCall.args[1];

      sinon.assert.calledOnceWithExactly(
        element.addEventListener,
        "scroll",
        onScroll,
        {passive: true},
      );

      detach();

      sinon.assert.calledOnceWithExactly(
        element.removeEventListener,
        "scroll",
        onScroll,
        {passive: true},
      );
    });

    it("keys each edge distinctly", () => {
      const keys = ["bottom", "left", "right", "top"].map(
        (edge) => EventListeners.scrollEdge(mockElement(), edge).key,
      );

      assert.strictEqual(new Set(keys).size, 4);
    });

    it("fires on mount when the edge is already within range", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 850,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);

      sinon.assert.calledOnceWithExactly(dispatcher, {target: element});
    });

    it("does not fire on mount when the edge is out of range", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);

      sinon.assert.notCalled(dispatcher);
    });

    it("fires on the transition into range, not again until it leaves and re-enters", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);
      const onScroll = element.addEventListener.firstCall.args[1];

      sinon.assert.notCalled(dispatcher);

      element.scrollTop = 850;
      onScroll();
      flushFrames();
      sinon.assert.calledOnce(dispatcher);

      onScroll();
      flushFrames();
      sinon.assert.calledOnce(dispatcher);

      element.scrollTop = 0;
      onScroll();
      flushFrames();
      sinon.assert.calledOnce(dispatcher);

      element.scrollTop = 850;
      onScroll();
      flushFrames();
      sinon.assert.calledTwice(dispatcher);
    });

    it("coalesces multiple scroll events into one check per frame", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);
      const onScroll = element.addEventListener.firstCall.args[1];

      element.scrollTop = 850;
      onScroll();
      onScroll();
      onScroll();

      assert.strictEqual(rafCallbacks.length, 1);

      flushFrames();
      sinon.assert.calledOnce(dispatcher);
    });

    it("cancels a pending frame on detach", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        sinon.spy(),
      );
      const onScroll = element.addEventListener.firstCall.args[1];

      onScroll();
      detach();

      sinon.assert.calledOnceWithExactly(globalThis.cancelAnimationFrame, 1);
    });

    it("observes the container for resize and disconnects on detach", () => {
      const element = mockElement();

      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        sinon.spy(),
      );

      const observer = resizeObservers[0];
      sinon.assert.calledOnceWithExactly(observer.observe, element);

      detach();

      sinon.assert.calledOnce(observer.disconnect);
    });

    it("rechecks when the container resizes", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);
      sinon.assert.notCalled(dispatcher);

      // The container grows, so the bottom edge falls within range.
      element.clientHeight = 950;
      resizeObservers[0].callback();
      flushFrames();

      sinon.assert.calledOnce(dispatcher);
    });

    it("measures the distance to each edge from the scroll metrics", () => {
      // Each metrics set leaves the bound edge 50px away, inside the default 100% range.
      const cases = [
        ["top", {clientHeight: 100, scrollTop: 50}],
        ["left", {clientWidth: 100, scrollLeft: 50}],
        ["bottom", {clientHeight: 100, scrollHeight: 1000, scrollTop: 850}],
        ["right", {clientWidth: 100, scrollWidth: 1000, scrollLeft: 850}],
      ];

      cases.forEach(([edge, metrics]) => {
        const dispatcher = sinon.spy();
        EventListeners.scrollEdge(mockElement(metrics), edge).attach(
          dispatcher,
        );
        sinon.assert.calledOnce(dispatcher);
      });
    });

    it("treats a pixel within as the threshold, overriding the default", () => {
      // The bottom edge is 200px away: outside the default 100px, inside within(200px).
      const metrics = {clientHeight: 100, scrollHeight: 1000, scrollTop: 700};

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(mockElement(metrics), "bottom", "200px").attach(
        dispatcher,
      );
      sinon.assert.calledOnce(dispatcher);

      const defaultDispatcher = sinon.spy();
      EventListeners.scrollEdge(mockElement(metrics), "bottom").attach(
        defaultDispatcher,
      );
      sinon.assert.notCalled(defaultDispatcher);
    });

    it("resolves a percentage within against the container", () => {
      // The bottom edge is 40px away; 50% of the 100px container is 50px, so it is within range.
      const metrics = {clientHeight: 100, scrollHeight: 1000, scrollTop: 860};

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(mockElement(metrics), "bottom", "50%").attach(
        dispatcher,
      );
      sinon.assert.calledOnce(dispatcher);
    });

    it("observes the container's children for resize", () => {
      const child1 = {};
      const child2 = {};
      const element = mockElement({children: [child1, child2]});

      EventListeners.scrollEdge(element, "bottom").attach(sinon.spy());
      const observer = resizeObservers[0];

      sinon.assert.calledWith(observer.observe, element);
      sinon.assert.calledWith(observer.observe, child1);
      sinon.assert.calledWith(observer.observe, child2);
    });

    it("re-fires while within range when the content grows", () => {
      // The bottom edge is 50px away, inside the default range, so it fires on mount.
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 150,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);
      sinon.assert.calledOnce(dispatcher);

      // Content grows but the edge is still within range.
      element.scrollHeight = 180;
      resizeObservers[0].callback();
      flushFrames();

      sinon.assert.calledTwice(dispatcher);
    });

    it("does not re-fire while within range when the content has not grown", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 150,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      EventListeners.scrollEdge(element, "bottom").attach(dispatcher);
      sinon.assert.calledOnce(dispatcher);

      resizeObservers[0].callback();
      flushFrames();

      sinon.assert.calledOnce(dispatcher);
    });

    it("re-syncs the observed children on recheckScrollEdges", () => {
      const child1 = {};
      const element = mockElement({children: [child1]});

      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        sinon.spy(),
      );
      const observer = resizeObservers[0];

      const child2 = {};
      element.children = [child2];
      EventListeners.recheckScrollEdges();

      sinon.assert.calledWith(observer.observe, child2);
      sinon.assert.calledWith(observer.unobserve, child1);

      detach();
    });

    it("recomputes against the patched DOM on recheckScrollEdges", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        dispatcher,
      );
      sinon.assert.notCalled(dispatcher);

      // A render shortens the content, bringing the bottom edge within range.
      element.scrollHeight = 150;
      EventListeners.recheckScrollEdges();
      flushFrames();

      sinon.assert.calledOnce(dispatcher);

      detach();
    });

    it("stops rechecking after detach", () => {
      const element = mockElement({
        clientHeight: 100,
        scrollHeight: 1000,
        scrollTop: 0,
      });

      const dispatcher = sinon.spy();
      const detach = EventListeners.scrollEdge(element, "bottom").attach(
        dispatcher,
      );
      detach();

      element.scrollHeight = 150;
      EventListeners.recheckScrollEdges();
      flushFrames();

      sinon.assert.notCalled(dispatcher);
    });
  });
});

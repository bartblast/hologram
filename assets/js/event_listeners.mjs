"use strict";

// Factories for the {key, attach} half of an EventListenerRegistry binding. Each returns a key
// that identifies the real listener among others on the same target, and an attach(dispatcher)
// that installs the listener wired to dispatcher and returns a detach() teardown. The registry
// owns the reconciliation; these own the transport - how a listener is actually installed - so a
// new transport (a DOM event, an observer) is a new factory here, not a registry change.
export default class EventListeners {
  // A DOM addEventListener/removeEventListener listener. The key separates a capture-phase
  // listener from a bubble-phase one for the same target and event, so the two reconcile as
  // independent listeners.
  static domEvent(target, eventName, capture = false) {
    return {
      key: `${capture ? "capture" : "bubble"}:${eventName}`,
      attach: (dispatcher) => {
        target.addEventListener(eventName, dispatcher, capture);
        return () => target.removeEventListener(eventName, dispatcher, capture);
      },
    };
  }

  // An IntersectionObserver listener for a single edge child of a scroll container, observed within
  // the container (the child's parent) as root. The key is per-edge, so a container's up-to-four
  // reach bindings reconcile independently and a re-render refreshes the matching edge rather than
  // stacking a second. Unlike the resize observer, the initial on-observe fire is kept: a container
  // whose edge is already in view at mount dispatches at once, so a short list keeps loading until
  // the viewport fills. Every fire dispatches its IntersectionObserverEntry. An optional margin -
  // the within modifier's CSS distance - overrides the default one-viewport prefetch lead.
  static intersectionObserver(element, edge, margin) {
    return {
      key: `intersection-observer:${edge}`,
      attach: (dispatcher) => {
        const observer = new IntersectionObserver(
          (entries) => dispatcher(entries[0]),
          {
            root: element.parentElement,
            rootMargin: $.#rootMargin(edge, margin),
          },
        );

        observer.observe(element);

        return () => observer.disconnect();
      },
    };
  }

  // A ResizeObserver listener for a single element. The key is constant - an element has at most
  // one resize observer - so a re-render refreshes it rather than stacking a second. The
  // observer's initial on-observe fire is suppressed, so $resize means "size changed" to match
  // the window resize event; every later change dispatches its ResizeObserverEntry.
  static resizeObserver(element) {
    return {
      key: "resize-observer",
      attach: (dispatcher) => {
        let initialFire = true;

        const observer = new ResizeObserver((entries) => {
          if (initialFire) {
            initialFire = false;
            return;
          }

          dispatcher(entries[0]);
        });

        observer.observe(element);

        return () => observer.disconnect();
      },
    };
  }

  // A scroll-offset listener for one edge of a scroll container, reading the container's own scroll
  // metrics rather than observing a child. The key is per-edge, so a container's up-to-four reach
  // bindings reconcile independently. Scroll events and the resize recompute are passive and
  // coalesced to one check per frame. Firing is edge-triggered - a per-edge in/out flag dispatches
  // on the transition into the within distance - and content-change-gated - it also dispatches while
  // still within range when the scrollable size has grown since the last fire, which drives
  // mount-fill and auto-fill. A ResizeObserver watches the container and its children, so a viewport
  // change or an item resizing (a late-loading image) rechecks. Every fire dispatches a {target}
  // carrying the container, as a scroll event has no per-binding target of its own.
  static scrollEdge(element, edge, within) {
    return {
      key: `scroll-edge:${edge}`,
      attach: (dispatcher) => {
        let wasWithin = false;
        let lastFiredSize = 0;
        let frame = null;

        const scrollSize = () =>
          edge === "top" || edge === "bottom"
            ? element.scrollHeight
            : element.scrollWidth;

        const check = () => {
          frame = null;

          const isWithin = $.#isWithinEdge(element, edge, within);
          const size = scrollSize();

          if (isWithin && (!wasWithin || size > lastFiredSize)) {
            dispatcher({target: element});
            lastFiredSize = size;
          }

          wasWithin = isWithin;
        };

        const schedule = () => {
          if (frame === null) {
            frame = requestAnimationFrame(check);
          }
        };

        const observer = new ResizeObserver(schedule);

        element.addEventListener("scroll", schedule, {passive: true});
        observer.observe(element);

        for (const child of element.children) {
          observer.observe(child);
        }

        check();

        return () => {
          element.removeEventListener("scroll", schedule, {passive: true});
          observer.disconnect();

          if (frame !== null) {
            cancelAnimationFrame(frame);
          }
        };
      },
    };
  }

  // Whether the container is scrolled within `within` of the given edge, measuring the distance to
  // that edge directly from the scroll metrics. A percentage resolves against the container's client
  // height (top/bottom) or width (left/right); a length is taken as pixels. Default is 100%.
  static #isWithinEdge(element, edge, within = "100%") {
    const vertical = edge === "top" || edge === "bottom";
    const clientSize = vertical ? element.clientHeight : element.clientWidth;

    const threshold = within.endsWith("%")
      ? (parseFloat(within) / 100) * clientSize
      : parseFloat(within);

    const distance = {
      bottom: element.scrollHeight - element.scrollTop - element.clientHeight,
      left: element.scrollLeft,
      right: element.scrollWidth - element.scrollLeft - element.clientWidth,
      top: element.scrollTop,
    }[edge];

    return distance <= threshold;
  }

  // Builds an IntersectionObserver rootMargin that extends the root's box past the binding's own
  // edge by the prefetch distance (default one viewport), leaving the other three sides flush, so
  // the event fires as that edge nears view. Components are in CSS "top right bottom left" order.
  static #rootMargin(edge, distance = "100%") {
    const margins = ["0px", "0px", "0px", "0px"];
    margins[{top: 0, right: 1, bottom: 2, left: 3}[edge]] = distance;

    return margins.join(" ");
  }
}

const $ = EventListeners;

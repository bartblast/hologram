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
  // bindings reconcile independently. The listener is passive and coalesced to one check per frame.
  // Firing is edge-triggered: a per-edge in/out flag dispatches only on the transition into the
  // within distance, so staying inside the distance does not re-fire. An initial check on attach
  // fires when the edge is already within range. Every fire dispatches a {target} carrying the
  // container, as a scroll event has no per-binding target of its own.
  static scrollEdge(element, edge, within) {
    return {
      key: `scroll-edge:${edge}`,
      attach: (dispatcher) => {
        let wasWithin = false;
        let frame = null;

        const check = () => {
          frame = null;

          const isWithin = $.#isWithinEdge(element, edge, within);

          if (isWithin && !wasWithin) {
            dispatcher({target: element});
          }

          wasWithin = isWithin;
        };

        const onScroll = () => {
          if (frame === null) {
            frame = requestAnimationFrame(check);
          }
        };

        element.addEventListener("scroll", onScroll, {passive: true});
        check();

        return () => {
          element.removeEventListener("scroll", onScroll, {passive: true});

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

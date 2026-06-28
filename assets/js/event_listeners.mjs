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

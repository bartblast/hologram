"use strict";

// Factories for the {key, attach} half of an EventListenerRegistry binding. Each returns a key
// that identifies the real listener among others on the same target, and an attach(dispatcher)
// that installs the listener wired to dispatcher and returns a detach() teardown. The registry
// owns the reconciliation; these own the transport - how a listener is actually installed - so a
// new transport (a DOM event, an observer) is a new factory here, not a registry change.
export default class EventListeners {
  static #scrollEdgeRechecks = new Set();

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

  // Rechecks every live scroll-edge listener. Run after a patch so each re-syncs the children its
  // ResizeObserver watches to the patched DOM and re-runs its check, driving auto-fill as a render
  // loads content.
  static recheckScrollEdges() {
    $.#scrollEdgeRechecks.forEach((recheck) => recheck());
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
  // change or an item resizing (a late-loading image) rechecks. recheckScrollEdges, run after each
  // patch, re-syncs the watched children to the patched DOM and recomputes, catching content a
  // render added. Every fire dispatches a {target} carrying the container, as a scroll event has no
  // per-binding target of its own.
  //
  // TODO: $reach_top / $reach_left do not preserve scroll position when content is prepended above
  // the viewport (the "load older content" pattern) - the view jumps. Native overflow-anchor would
  // hold the view, but only once list children are keyed so a prepend reconciles as an insert-before
  // instead of positional in-place mutation. Tracked by keyed lists (#876), revisit when that lands.
  static scrollEdge(element, edge, within) {
    return {
      // within is part of the key: the listener closes over it, and a retained (target, key) entry
      // keeps its attachment without re-running attach, so a changed within must key a fresh one.
      key: `scroll-edge:${edge}:${within}`,
      attach: (dispatcher) => {
        let wasWithin = false;
        let lastFiredSize = 0;
        let frame = null;
        let observed = new Set();

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

        // Watch each child so an item resizing rechecks; re-sync to the live children on recheck.
        const syncChildren = () => {
          const children = new Set(element.children);

          observed.forEach((child) => {
            if (!children.has(child)) {
              observer.unobserve(child);
            }
          });

          children.forEach((child) => {
            if (!observed.has(child)) {
              observer.observe(child);
            }
          });

          observed = children;
        };

        const recheck = () => {
          syncChildren();
          schedule();
        };

        element.addEventListener("scroll", schedule, {passive: true});
        observer.observe(element);
        syncChildren();
        $.#scrollEdgeRechecks.add(recheck);

        // Defer the mount check to the next frame instead of running it synchronously: attach runs
        // inside the render's reconcile, so a synchronous fire would dispatch an action that
        // re-renders re-entrantly, re-attaching mid-render. Scheduling lets the mount-fire (and the
        // auto-fill of a container the content does not fill) happen once the render has settled.
        schedule();

        return () => {
          $.#scrollEdgeRechecks.delete(recheck);
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
}

const $ = EventListeners;

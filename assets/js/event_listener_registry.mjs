"use strict";

// One reconciled listener per (target, DOM event name, phase). Window and document event bindings
// have no DOM node to host them, so the registry installs exactly one real listener per
// (target, event name, capture flag) and fans it out to every binding for that triple. The desired
// set is rebuilt each render and reconciled against the live set, per target: a listener gaining its
// first binding adds a real listener, losing its last binding removes it, and one present in both
// keeps its listener and just swaps its handler list (read lazily at dispatch), so ordinary
// re-renders cause no listener churn. Targets are reconciled independently of one another.
//
// The capture flag lets a binding listen in the capture phase instead of the default bubble phase.
// Click-outside needs it: Hologram renders synchronously inside the click handler, so a bubble-phase
// document listener installed while the opening click is still bubbling would fire for that very
// click and immediately dismiss the element. A capture-phase listener installed at that point does
// not - the capture phase has already passed - so the opening click is never seen as an outside one.
export default class EventListenerRegistry {
  static #entriesByTarget = new Map();

  // Reconciles the live listeners against `bindings`, an array of {target, eventName, handler,
  // capture} descriptors collected during the current render (capture defaults to false). Adds,
  // refreshes, or removes exactly one real listener per (target, event name, capture) so the live
  // set matches current demand.
  static reconcile(bindings) {
    const desiredByTarget = new Map();

    for (const {target, eventName, handler, capture = false} of bindings) {
      let desiredByKey = desiredByTarget.get(target);

      if (desiredByKey === undefined) {
        desiredByKey = new Map();
        desiredByTarget.set(target, desiredByKey);
      }

      const key = $.#listenerKey(eventName, capture);
      let desired = desiredByKey.get(key);

      if (desired === undefined) {
        desired = {eventName, capture, handlers: []};
        desiredByKey.set(key, desired);
      }

      desired.handlers.push(handler);
    }

    // Add or refresh: an existing (target, event, capture) entry keeps its real listener and just
    // swaps its handler list; a new one gets one real listener whose dispatcher reads the entry's
    // handlers lazily, so a later refresh takes effect without re-registering.
    for (const [target, desiredByKey] of desiredByTarget) {
      let liveByKey = $.#entriesByTarget.get(target);

      if (liveByKey === undefined) {
        liveByKey = new Map();
        $.#entriesByTarget.set(target, liveByKey);
      }

      for (const [key, desired] of desiredByKey) {
        const entry = liveByKey.get(key);

        if (entry === undefined) {
          const newEntry = {
            dispatcher: null,
            eventName: desired.eventName,
            capture: desired.capture,
            handlers: desired.handlers,
          };

          newEntry.dispatcher = (event) =>
            newEntry.handlers.forEach((handler) => handler(event));

          target.addEventListener(
            desired.eventName,
            newEntry.dispatcher,
            desired.capture,
          );

          liveByKey.set(key, newEntry);
        } else {
          entry.handlers = desired.handlers;
        }
      }
    }

    // Remove: any live (target, event, capture) absent from this render has lost its last binding,
    // so drop its real listener. A target left with no listeners drops out of the registry.
    for (const [target, liveByKey] of $.#entriesByTarget) {
      const desiredByKey = desiredByTarget.get(target);

      for (const [key, entry] of liveByKey) {
        if (desiredByKey === undefined || !desiredByKey.has(key)) {
          target.removeEventListener(
            entry.eventName,
            entry.dispatcher,
            entry.capture,
          );

          liveByKey.delete(key);
        }
      }

      if (liveByKey.size === 0) {
        $.#entriesByTarget.delete(target);
      }
    }
  }

  // Composite key distinguishing a capture-phase listener from a bubble-phase one for the same
  // target and event name, so the two reconcile as independent listeners.
  static #listenerKey(eventName, capture) {
    return `${capture ? "capture" : "bubble"}\0${eventName}`;
  }
}

const $ = EventListenerRegistry;

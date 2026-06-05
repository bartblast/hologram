"use strict";

// One reconciled listener per (target, DOM event name). Global event bindings (<window>,
// <document>) have no DOM node to host them, so the registry installs exactly one real listener per
// (target, event name) and fans it out to every binding for that pair. The desired set is rebuilt
// each render and reconciled against the live set, per target: an event name gaining its first
// binding on a target adds a real listener, losing its last binding removes it, and one present in
// both keeps its listener and just swaps its handler list (read lazily at dispatch), so ordinary
// re-renders cause no listener churn. Targets are reconciled independently of one another.
export default class GlobalEventRegistry {
  static #entriesByTarget = new Map();

  // Reconciles the live listeners against `bindings`, an array of {target, eventName, handler}
  // descriptors collected during the current render. Adds, refreshes, or removes exactly one real
  // listener per (target, event name) so the live set matches current demand.
  static reconcile(bindings) {
    const desiredByTarget = new Map();

    for (const {target, eventName, handler} of bindings) {
      let handlersByEvent = desiredByTarget.get(target);

      if (handlersByEvent === undefined) {
        handlersByEvent = new Map();
        desiredByTarget.set(target, handlersByEvent);
      }

      let handlers = handlersByEvent.get(eventName);

      if (handlers === undefined) {
        handlers = [];
        handlersByEvent.set(eventName, handlers);
      }

      handlers.push(handler);
    }

    // Add or refresh: an existing (target, event) entry keeps its real listener and just swaps its
    // handler list; a new one gets one real listener whose dispatcher reads the entry's handlers
    // lazily, so a later refresh takes effect without re-registering.
    for (const [target, handlersByEvent] of desiredByTarget) {
      let liveByEvent = $.#entriesByTarget.get(target);

      if (liveByEvent === undefined) {
        liveByEvent = new Map();
        $.#entriesByTarget.set(target, liveByEvent);
      }

      for (const [eventName, handlers] of handlersByEvent) {
        const entry = liveByEvent.get(eventName);

        if (entry === undefined) {
          const newEntry = {dispatcher: null, handlers};

          newEntry.dispatcher = (event) =>
            newEntry.handlers.forEach((handler) => handler(event));

          target.addEventListener(eventName, newEntry.dispatcher);
          liveByEvent.set(eventName, newEntry);
        } else {
          entry.handlers = handlers;
        }
      }
    }

    // Remove: any live (target, event) absent from this render has lost its last binding, so drop
    // its real listener. A target left with no listeners drops out of the registry.
    for (const [target, liveByEvent] of $.#entriesByTarget) {
      const handlersByEvent = desiredByTarget.get(target);

      for (const [eventName, entry] of liveByEvent) {
        if (handlersByEvent === undefined || !handlersByEvent.has(eventName)) {
          target.removeEventListener(eventName, entry.dispatcher);
          liveByEvent.delete(eventName);
        }
      }

      if (liveByEvent.size === 0) {
        $.#entriesByTarget.delete(target);
      }
    }
  }
}

const $ = GlobalEventRegistry;

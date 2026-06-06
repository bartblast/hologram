"use strict";

// One reconciled listener per (target, key). Window and document event bindings have no DOM node
// to host them, so the registry installs exactly one real listener per (target, key) and fans it
// out to every binding for that pair. The desired set is rebuilt each render and reconciled
// against the live set, per target: a listener gaining its first binding attaches a real listener,
// losing its last binding detaches it, and one present in both keeps its listener and just swaps
// its handler list (read lazily at dispatch), so ordinary re-renders cause no listener churn.
// Targets are reconciled independently of one another.
//
// How a listener is actually installed - a DOM addEventListener, a ResizeObserver - is the
// binding's own concern: each carries an attach(dispatcher) that installs the real listener and
// returns a detach() teardown (see event_listeners.mjs). The key tells listeners on one target
// apart - a capture-phase listener from a bubble-phase one, a DOM event from an observer - so
// each reconciles independently.
export default class EventListenerRegistry {
  static #entriesByTarget = new Map();

  // Reconciles the live listeners against `bindings`, an array of {target, key, attach, handler}
  // descriptors collected during the current render. Attaches, refreshes, or detaches exactly one
  // real listener per (target, key) so the live set matches current demand.
  static reconcile(bindings) {
    const desiredByTarget = new Map();

    for (const {target, key, attach, handler} of bindings) {
      let desiredByKey = desiredByTarget.get(target);

      if (desiredByKey === undefined) {
        desiredByKey = new Map();
        desiredByTarget.set(target, desiredByKey);
      }

      let desired = desiredByKey.get(key);

      if (desired === undefined) {
        desired = {attach, handlers: []};
        desiredByKey.set(key, desired);
      }

      desired.handlers.push(handler);
    }

    // Attach or refresh: an existing (target, key) entry keeps its real listener and just swaps its
    // handler list; a new one attaches one real listener whose dispatcher reads the entry's
    // handlers lazily, so a later refresh takes effect without re-attaching.
    for (const [target, desiredByKey] of desiredByTarget) {
      let liveByKey = $.#entriesByTarget.get(target);

      if (liveByKey === undefined) {
        liveByKey = new Map();
        $.#entriesByTarget.set(target, liveByKey);
      }

      for (const [key, desired] of desiredByKey) {
        const entry = liveByKey.get(key);

        if (entry === undefined) {
          const newEntry = {detach: null, handlers: desired.handlers};

          newEntry.detach = desired.attach((event) =>
            newEntry.handlers.forEach((handler) => handler(event)),
          );

          liveByKey.set(key, newEntry);
        } else {
          entry.handlers = desired.handlers;
        }
      }
    }

    // Detach: any live (target, key) absent from this render has lost its last binding, so tear
    // down its real listener. A target left with no listeners drops out of the registry.
    for (const [target, liveByKey] of $.#entriesByTarget) {
      const desiredByKey = desiredByTarget.get(target);

      for (const [key, entry] of liveByKey) {
        if (desiredByKey === undefined || !desiredByKey.has(key)) {
          entry.detach();
          liveByKey.delete(key);
        }
      }

      if (liveByKey.size === 0) {
        $.#entriesByTarget.delete(target);
      }
    }
  }
}

const $ = EventListenerRegistry;

"use strict";

// One reconciled window-level listener per DOM event name. Window event bindings have no DOM node
// to host them, so the registry installs exactly one real window listener per event name and fans
// it out to every binding for that event. The desired set is rebuilt each render and reconciled
// against the live set: an event name gaining its first binding adds a real listener, an event name
// losing its last binding removes it, and an event name present in both keeps its listener and just
// swaps its handler list (read lazily at dispatch), so ordinary re-renders cause no listener churn.
export default class WindowEventRegistry {
  static #entriesByEvent = new Map();

  // Reconciles the live window listeners against `bindings`, an array of {eventName, handler}
  // descriptors collected during the current render. Adds, refreshes, or removes exactly one real
  // window listener per event name so the live set matches current demand.
  static reconcile(bindings) {
    const handlersByEvent = new Map();

    for (const {eventName, handler} of bindings) {
      let handlers = handlersByEvent.get(eventName);

      if (handlers === undefined) {
        handlers = [];
        handlersByEvent.set(eventName, handlers);
      }

      handlers.push(handler);
    }

    // Add or refresh: an event name already live keeps its real listener and just swaps its handler
    // list; a new event name gets one real listener whose dispatcher reads the entry's handlers
    // lazily, so a later refresh takes effect without re-registering.
    for (const [eventName, handlers] of handlersByEvent) {
      const entry = $.#entriesByEvent.get(eventName);

      if (entry === undefined) {
        const newEntry = {dispatcher: null, handlers};

        newEntry.dispatcher = (event) =>
          newEntry.handlers.forEach((handler) => handler(event));

        window.addEventListener(eventName, newEntry.dispatcher);
        $.#entriesByEvent.set(eventName, newEntry);
      } else {
        entry.handlers = handlers;
      }
    }

    // Remove: any live event name absent from this render has lost its last binding, so drop its
    // real listener.
    for (const [eventName, entry] of $.#entriesByEvent) {
      if (!handlersByEvent.has(eventName)) {
        window.removeEventListener(eventName, entry.dispatcher);
        $.#entriesByEvent.delete(eventName);
      }
    }
  }
}

const $ = WindowEventRegistry;

"use strict";

// Factories for the {key, attach} half of an EventListenerRegistry binding. Each returns a key
// that identifies the real listener among others on the same target, and an attach(dispatcher)
// that installs the listener wired to dispatcher and returns a detach() teardown. The registry
// owns the reconciliation; these own the transport - how a listener is actually installed - so a
// new transport (a DOM event, an observer) is a new factory here, not a registry change.
export default class Listeners {
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
}

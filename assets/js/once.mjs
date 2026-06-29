"use strict";

// One-shot fired-state keyed by (element, slotKey). Whether a once binding has already fired lives
// in a WeakMap keyed by the live DOM element, so it survives event-listener recreation across
// re-renders (the element is patched in place) and is collected when the element leaves the DOM, so
// a re-created element is a fresh key whose binding re-arms. The inner set keys by a per-binding
// slot, so several once bindings on one element each track their own fired-state.
export default class Once {
  static #firedSlotsByElement = new WeakMap();

  // Returns true if the (element, slotKey) binding has already fired.
  static hasFired(element, slotKey) {
    const firedSlots = $.#firedSlotsByElement.get(element);
    return firedSlots !== undefined && firedSlots.has(slotKey);
  }

  // Records that the (element, slotKey) binding has fired. Idempotent.
  static markFired(element, slotKey) {
    let firedSlots = $.#firedSlotsByElement.get(element);

    if (firedSlots === undefined) {
      firedSlots = new Set();
      $.#firedSlotsByElement.set(element, firedSlots);
    }

    firedSlots.add(slotKey);
  }
}

const $ = Once;

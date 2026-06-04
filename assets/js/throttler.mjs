"use strict";

// Leading-and-trailing throttle keyed by (element, slotKey). Window state lives in a WeakMap keyed
// by the live DOM element, so it survives event-listener recreation across re-renders (the element
// is patched in place) and is collected when the element leaves the DOM. The inner map keys by a
// per-binding slot, so several throttled bindings on one element and DOM event each keep an
// independent window.
export default class Throttler {
  static #slotsByElement = new WeakMap();

  // Dispatches callback at most once per delayMs for the given (element, slotKey). The first call
  // fires immediately (leading edge); calls arriving during the window are held and the latest
  // fires when the window ends (trailing edge), which opens the next window. When activity stops
  // the slot goes idle and the next call is a fresh leading edge.
  static run(element, slotKey, delayMs, callback) {
    let slots = $.#slotsByElement.get(element);

    if (slots === undefined) {
      slots = new Map();
      $.#slotsByElement.set(element, slots);
    }

    const slot = slots.get(slotKey);

    if (slot === undefined) {
      // Idle: open the window first (so a re-entrant call lands inside it), then dispatch.
      slots.set(slotKey, {pending: null});
      $.#openWindow(slots, slotKey, delayMs);
      callback();
    } else {
      // Inside the window: hold the latest call for the trailing edge.
      slot.pending = callback;
    }
  }

  static #closeWindow(slots, slotKey, delayMs) {
    const slot = slots.get(slotKey);

    if (slot.pending === null) {
      // No call arrived during the window: go idle.
      slots.delete(slotKey);
    } else {
      // Trailing edge: dispatch the latest call and open a fresh window.
      const callback = slot.pending;
      slot.pending = null;
      $.#openWindow(slots, slotKey, delayMs);
      callback();
    }
  }

  static #openWindow(slots, slotKey, delayMs) {
    setTimeout(() => $.#closeWindow(slots, slotKey, delayMs), delayMs);
  }
}

const $ = Throttler;

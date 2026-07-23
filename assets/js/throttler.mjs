"use strict";

// Leading-and-trailing throttle keyed by (element, slotKey). Each slot holds its window timer id
// and any held trailing dispatch, so open windows can be dropped before they close. Slots live in
// a regular Map keyed by the live DOM element - safe despite the strong reference because every
// slot is short-lived by construction (windows are brief by design and an idle slot is removed)
// and an element whose last slot empties is removed from the map. Window state survives
// event-listener recreation across re-renders (the element is patched in place). The inner map
// keys by a per-binding slot, so several throttled bindings on one element and DOM event each
// keep an independent window.
export default class Throttler {
  static #slotsByElement = new Map();

  // Clears every open window and held trailing dispatch and empties the state without firing
  // anything.
  static cancelAll() {
    for (const slots of $.#slotsByElement.values()) {
      for (const {timerId} of slots.values()) {
        clearTimeout(timerId);
      }
    }

    $.#slotsByElement.clear();
  }

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
      slots.set(slotKey, {pending: null, timerId: null});
      $.#openWindow(element, slots, slotKey, delayMs);
      callback();
    } else {
      // Inside the window: hold the latest call for the trailing edge.
      slot.pending = callback;
    }
  }

  static #closeWindow(element, slots, slotKey, delayMs) {
    const slot = slots.get(slotKey);

    if (slot.pending === null) {
      // No call arrived during the window: go idle.
      $.#deleteSlot(element, slots, slotKey);
    } else {
      // Trailing edge: dispatch the latest call and open a fresh window.
      const callback = slot.pending;
      slot.pending = null;
      $.#openWindow(element, slots, slotKey, delayMs);
      callback();
    }
  }

  static #deleteSlot(element, slots, slotKey) {
    slots.delete(slotKey);

    if (slots.size === 0) {
      $.#slotsByElement.delete(element);
    }
  }

  static #openWindow(element, slots, slotKey, delayMs) {
    slots.get(slotKey).timerId = setTimeout(
      () => $.#closeWindow(element, slots, slotKey, delayMs),
      delayMs,
    );
  }
}

const $ = Throttler;

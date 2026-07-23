"use strict";

// Trailing-edge debounce keyed by (element, slotKey). Each pending entry holds its timer id and
// dispatch callback, so a dispatch can be fired early (flush) or dropped before the timer fires.
// Entries live in a regular Map keyed by the live DOM element - safe despite the strong reference
// because every entry is short-lived by construction (it fires, flushes, or is cancelled) and an
// element whose last slot empties is removed from the map. Timers survive event-listener
// recreation across re-renders (the element is patched in place). The inner map keys by a
// per-binding slot, so several debounced bindings on one element and DOM event each keep an
// independent timer.
export default class Debouncer {
  static #pendingByElement = new Map();

  // Immediately fires and removes all pending entries keyed on the element, in the order their
  // slots were first scheduled. No-op when none are pending. Entries are removed before their
  // callbacks run, so a callback that schedules a new debounced run re-enters cleanly.
  static flush(element) {
    const slots = $.#pendingByElement.get(element);

    if (slots === undefined) {
      return;
    }

    $.#pendingByElement.delete(element);

    for (const {timerId, callback} of slots.values()) {
      clearTimeout(timerId);
      callback();
    }
  }

  // Immediately fires and removes all pending entries whose element is inside the container
  // (including the container itself), in the order their slots were first scheduled. Entries keyed
  // on non-node targets (window and document bindings) are skipped - they have no place in the
  // element tree, so no container can scope them.
  static flushWithin(container) {
    // Keys are copied first: flush deletes entries, and a flushed callback may schedule new ones.
    for (const element of [...$.#pendingByElement.keys()]) {
      if (element.nodeType !== undefined && container.contains(element)) {
        $.flush(element);
      }
    }
  }

  // Schedules callback to run after delayMs, canceling any pending run for the same
  // (element, slotKey). Each call restarts the window, so only the final call in a burst fires.
  static run(element, slotKey, delayMs, callback) {
    let slots = $.#pendingByElement.get(element);

    if (slots === undefined) {
      slots = new Map();
      $.#pendingByElement.set(element, slots);
    }

    const pending = slots.get(slotKey);

    if (pending !== undefined) {
      clearTimeout(pending.timerId);
    }

    const timerId = setTimeout(() => {
      $.#deleteSlot(element, slots, slotKey);
      callback();
    }, delayMs);

    slots.set(slotKey, {timerId, callback});
  }

  static #deleteSlot(element, slots, slotKey) {
    slots.delete(slotKey);

    if (slots.size === 0) {
      $.#pendingByElement.delete(element);
    }
  }
}

const $ = Debouncer;

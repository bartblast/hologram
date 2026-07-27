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

  // Clears every pending timer and empties the registry without firing anything.
  static cancelAll() {
    for (const slots of $.#pendingByElement.values()) {
      for (const {timerId} of slots.values()) {
        clearTimeout(timerId);
      }
    }

    $.#pendingByElement.clear();
  }

  // Immediately fires and removes all pending entries keyed on the element, in the order their
  // slots were first scheduled. No-op when none are pending. Entries are removed before their
  // callbacks run, so a callback that schedules a new debounced run re-enters cleanly. A callback
  // runs app code and may throw - a throw stops neither the disarming nor the delivery of the
  // remaining dispatches, and the first error is rethrown once the flush completes.
  static flush(element) {
    const slots = $.#pendingByElement.get(element);

    if (slots === undefined) {
      return;
    }

    $.#pendingByElement.delete(element);

    // Disarm every timer before dispatching anything, so no slot is left armed to fire after the
    // boundary the flush resolved.
    const callbacks = [];

    for (const {timerId, callback} of slots.values()) {
      clearTimeout(timerId);
      callbacks.push(callback);
    }

    let firstError;

    for (const callback of callbacks) {
      try {
        callback();
      } catch (error) {
        firstError ??= error;
      }
    }

    if (firstError !== undefined) {
      throw firstError;
    }
  }

  // Immediately fires and removes all pending entries whose element is inside the container
  // (including the container itself), in the order their slots were first scheduled. Entries keyed
  // on non-node targets (window and document bindings) are skipped - they have no place in the
  // element tree, so no container can scope them. A throw in one element's flush stops neither
  // the disarming nor the delivery for the remaining elements, and the first error is rethrown
  // once the whole container is flushed.
  static flushWithin(container) {
    // Keys are copied first: flush deletes entries, and a flushed callback may schedule new ones.
    let firstError;

    for (const element of [...$.#pendingByElement.keys()]) {
      if (element.nodeType !== undefined && container.contains(element)) {
        try {
          $.flush(element);
        } catch (error) {
          firstError ??= error;
        }
      }
    }

    if (firstError !== undefined) {
      throw firstError;
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

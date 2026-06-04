"use strict";

// Trailing-edge debounce keyed by (element, slotKey). Timers live in a WeakMap keyed by the live
// DOM element, so they survive event-listener recreation across re-renders (the element is patched
// in place) and are collected when the element leaves the DOM. The inner map keys by a per-binding
// slot, so several debounced bindings on one element and DOM event each keep an independent timer.
export default class Debouncer {
  static #timersByElement = new WeakMap();

  // Schedules callback to run after delayMs, canceling any pending run for the same
  // (element, slotKey). Each call restarts the window, so only the final call in a burst fires.
  static run(element, slotKey, delayMs, callback) {
    let timers = $.#timersByElement.get(element);

    if (timers === undefined) {
      timers = new Map();
      $.#timersByElement.set(element, timers);
    }

    // clearTimeout(undefined) is a no-op, so the first run in a slot needs no guard.
    clearTimeout(timers.get(slotKey));

    const timerId = setTimeout(() => {
      timers.delete(slotKey);
      callback();
    }, delayMs);

    timers.set(slotKey, timerId);
  }
}

const $ = Debouncer;

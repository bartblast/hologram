"use strict";

// The actions waiting to run, in the order they arrived. Every entry carries the epoch of the page
// the action belongs to (see Hologram.enqueueAction). The queue holds the entries and nothing else:
// Hologram runs them.
export default class ActionQueue {
  // Made public to make tests easier
  static entries = [];

  // Adds the given entries at the end of the queue, in their order.
  static append(entries) {
    $.entries.push(...entries);
  }

  // Empties the queue and returns the entries it held, in their order.
  static drain() {
    const entries = $.entries;
    $.entries = [];

    return entries;
  }

  static enqueue(action, epoch) {
    $.entries.push({action: action, epoch: epoch});
  }

  // Removes the entry at the given position and returns it.
  static removeAt(index) {
    return $.entries.splice(index, 1)[0];
  }
}

const $ = ActionQueue;

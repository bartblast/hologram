"use strict";

// The actions waiting to run, in the order they arrived. Every entry carries the epoch of the page
// the action belongs to (see Hologram.enqueueAction). The queue holds the entries and nothing else:
// Hologram runs them.
export default class ActionQueue {
  // Made public to make tests easier
  static entries = [];

  static enqueue(action, epoch) {
    $.entries.push({action: action, epoch: epoch});
  }

  static isEmpty() {
    return $.entries.length === 0;
  }

  static peek() {
    return $.entries[0];
  }

  static shift() {
    return $.entries.shift();
  }
}

const $ = ActionQueue;

"use strict";

export default class InitActionQueue {
  // Made public to make tests easier
  static queue = [];

  static dequeueAll() {
    const actions = [...$.queue];
    $.queue = [];

    return actions;
  }

  static enqueue(action) {
    $.queue.push(action);
  }
}

const $ = InitActionQueue;

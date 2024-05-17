"use strict";

export default class CommandQueue {
  // Made public to make tests easier
  static items = {};

  // Made public to make tests easier
  static getNextPending() {
    // The traversal order for string keys is ascending chronological (so we get FIFO behaviour)
    for (const id in CommandQueue.items) {
      if (CommandQueue.items[id].status === "pending") {
        return CommandQueue.items[id];
      }
    }

    return null;
  }

  static push(command) {
    const id = crypto.randomUUID();

    CommandQueue.items[id] = {
      id: id,
      command: command,
      status: "pending",
    };
  }

  static remove(id) {
    delete CommandQueue.items[id];
  }
}

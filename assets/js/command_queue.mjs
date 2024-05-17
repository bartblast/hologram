"use strict";

export default class CommandQueue {
  // Made public to make tests easier
  static items = {};

  static push(command) {
    const id = crypto.randomUUID();

    CommandQueue.items[id] = {
      id: id,
      command: command,
      status: "pending",
    };
  }
}

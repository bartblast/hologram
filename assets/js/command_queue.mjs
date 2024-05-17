"use strict";

import Client from "./client.mjs";

export default class CommandQueue {
  // Made public to make tests easier
  static isProcessing = false;

  // Made public to make tests easier
  static items = {};

  static fail(id) {
    CommandQueue.items[id].status = "failed";
    ++CommandQueue.items[id].failCount;
  }

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

  static async process() {
    if (!CommandQueue.isProcessing && Client.isConnected()) {
      CommandQueue.isProcessing = true;

      let item;

      while ((item = CommandQueue.getNextPending())) {
        item.status = "sending";

        const successCallback = ((currentItem) => {
          return () => CommandQueue.remove(currentItem.id);
        })(item);

        const failureCallback = ((currentItem) => {
          return () => CommandQueue.fail(currentItem.id);
        })(item);

        Client.push("command", item.command, successCallback, failureCallback);
      }

      CommandQueue.isProcessing = false;
    }
  }

  static push(command) {
    const id = crypto.randomUUID();

    CommandQueue.items[id] = {
      id: id,
      command: command,
      status: "pending",
      failCount: 0,
    };
  }

  static remove(id) {
    delete CommandQueue.items[id];
  }

  static size() {
    return Object.keys(CommandQueue.items).length;
  }
}

"use strict";

import Bitstring from "./bitstring.mjs";
import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

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
          return (resp) => {
            CommandQueue.remove(currentItem.id);

            const nextAction = Utils.evaluate(resp);

            if (!Type.isNil(nextAction)) {
              Hologram.executeAction(nextAction);
            }
          };
        })(item);

        const failureCallback = ((currentItem) => {
          return () => CommandQueue.fail(currentItem.id);
        })(item);

        const payload = CommandQueue.#buildPayload(item);

        Client.push("command", payload, successCallback, failureCallback);
      }

      CommandQueue.isProcessing = false;
    }
  }

  // Deps: [:maps.get/2]
  static push(command) {
    const id = crypto.randomUUID();
    const target = Erlang_Maps["get/2"](Type.atom("target"), command);
    const module = ComponentRegistry.getComponentModule(target);

    if (module === null) {
      Interpreter.raiseError(
        "Hologram.RuntimeError",
        `invalid command target: "${Bitstring.toText(target)}"`,
      );
    }

    CommandQueue.items[id] = {
      id: id,
      failCount: 0,
      module: module,
      name: Erlang_Maps["get/2"](Type.atom("name"), command),
      params: Erlang_Maps["get/2"](Type.atom("params"), command),
      status: "pending",
      target: target,
    };
  }

  static remove(id) {
    delete CommandQueue.items[id];
  }

  static size() {
    return Object.keys(CommandQueue.items).length;
  }

  static #buildPayload(item) {
    return Type.map([
      [Type.atom("module"), item.module],
      [Type.atom("name"), item.name],
      [Type.atom("params"), item.params],
      [Type.atom("target"), item.target],
    ]);
  }
}

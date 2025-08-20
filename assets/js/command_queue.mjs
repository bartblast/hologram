"use strict";

import Client from "./client.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Hologram from "./hologram.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class CommandQueue {
  // Made public to make tests easier
  static isProcessing = false;

  // Made public to make tests easier
  static items = {};

  static fail(id) {
    CommandQueue.items[id].status = "failed";
    ++CommandQueue.items[id].failCount;
  }

  static failAndThrowError(id, message) {
    CommandQueue.fail(id);
    throw new HologramRuntimeError(`command failed: ${message}`);
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

  static process() {
    if (!CommandQueue.isProcessing && Client.isConnected()) {
      CommandQueue.isProcessing = true;

      let item;

      while ((item = CommandQueue.getNextPending())) {
        item.status = "sending";

        const successCallback = ((currentItem) => {
          return (responsePayload) => {
            const [status, result] = responsePayload;

            if (status === 1) {
              CommandQueue.remove(currentItem.id);

              const nextAction =
                Interpreter.evaluateJavaScriptExpression(result);

              if (!Type.isNil(nextAction)) {
                // Execute next action asynchronously to allow animations and prevent blocking the event loop
                setTimeout(() => Hologram.executeAction(nextAction), 0);
              }
            } else {
              $.failAndThrowError(currentItem.id, result);
            }
          };
        })(item);

        const failureCallback = ((currentItem) => {
          return (responsePayload) => {
            $.failAndThrowError(currentItem.id, responsePayload);
          };
        })(item);

        const payload = CommandQueue.#buildPayload(item);

        Client.sendCommand(payload, successCallback, failureCallback);
      }

      CommandQueue.isProcessing = false;
    }
  }

  // Deps: [:maps.get/2]
  static push(command) {
    const target = Erlang_Maps["get/2"](Type.atom("target"), command);

    if (!ComponentRegistry.isCidRegistered(target)) {
      const msg = `invalid command target, there is no component with CID: ${Interpreter.inspect(target)}`;
      throw new HologramRuntimeError(msg);
    }

    const id = crypto.randomUUID();
    const module = ComponentRegistry.getComponentModule(target);

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

const $ = CommandQueue;

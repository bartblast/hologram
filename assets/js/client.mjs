"use strict";

import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Connection from "./connection.mjs";
import Hologram from "./hologram.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Client {
  // Covered in feature tests
  static connect() {
    return Connection.connect();
  }

  // Covered in feature tests
  static fetchPage(toParam, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
      timeout: Config.fetchPageTimeoutMs,
    };

    return Connection.sendRequest("page", toParam, opts);
  }

  // Covered in feature tests
  static fetchPageBundlePath(pageModule, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
      timeout: Config.clientFetchTimeoutMs,
    };

    return Connection.sendRequest("page_bundle_path", pageModule, opts);
  }

  // Covered in feature tests
  static isConnected() {
    return Connection.isConnected();
  }

  static async sendCommand(command) {
    const opts = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: $.buildCommandPayload(command),
    };

    try {
      const response = await fetch("/hologram/command", opts);

      if (!response.ok) {
        $.#failCommand(response.status);
      }

      const [status, result] = await response.json();

      if (status === 0) {
        $.#failCommand(result);
      }

      const nextAction = Interpreter.evaluateJavaScriptExpression(result);

      if (!Type.isNil(nextAction)) {
        Hologram.executeAction(nextAction);
      }
    } catch (error) {
      $.#failCommand(error);
    }
  }

  // Deps: [:maps.get/2]
  static buildCommandPayload(command) {
    const target = Erlang_Maps["get/2"](Type.atom("target"), command);

    if (!ComponentRegistry.isCidRegistered(target)) {
      const message = `invalid command target, there is no component with CID: ${Interpreter.inspect(target)}`;
      throw new HologramRuntimeError(message);
    }

    const module = ComponentRegistry.getComponentModule(target);

    return Type.map([
      [Type.atom("module"), module],
      [Type.atom("name"), Erlang_Maps["get/2"](Type.atom("name"), command)],
      [Type.atom("params"), Erlang_Maps["get/2"](Type.atom("params"), command)],
      [Type.atom("target"), target],
    ]);
  }

  static #failCommand(message) {
    throw new HologramRuntimeError(`command failed: ${message}`);
  }
}

const $ = Client;

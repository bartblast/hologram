"use strict";

import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Connection from "./connection.mjs";
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

  // TODO: test
  static sendCommand(payload, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
    };

    return Connection.sendRequest("command", payload, opts);
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
}

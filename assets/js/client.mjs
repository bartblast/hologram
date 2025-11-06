"use strict";

import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Connection from "./connection.mjs";
import Hologram from "./hologram.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import HttpTransport from "./http_transport.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Client {
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

  static buildPageQueryString(params) {
    if (Type.isList(params)) {
      params = Type.map(
        params.data.map((param) => [param.data[0], param.data[1]]),
      );
    }

    let queryParts = [];

    Object.values(params.data).forEach((param) => {
      const key = param[0];

      if (key.type !== "atom") {
        throw new HologramRuntimeError(
          `invalid param key type (only atom type is allowed), got: ${Interpreter.inspect(key)}`,
        );
      }

      const value = param[1];

      if (
        value.type !== "atom" &&
        value.type !== "float" &&
        value.type !== "integer" &&
        !Type.isBinary(value)
      ) {
        throw new HologramRuntimeError(
          `invalid param value type (only atom, float, integer and string types are allowed), got: ${Interpreter.inspect(value)}`,
        );
      }

      const encodedKey = encodeURIComponent(key.value);
      const rawValue = Type.isBitstring(value)
        ? Bitstring.toText(value)
        : value.value.toString();
      const encodedValue = encodeURIComponent(rawValue);

      queryParts.push(`${encodedKey}=${encodedValue}`);
    });

    return queryParts.length > 0 ? `?${queryParts.join("&")}` : "";
  }

  static connect(sendImmediatePing) {
    Connection.connect();
    HttpTransport.restartPing(sendImmediatePing);
  }

  static async fetchPage(toParam, onSuccess) {
    let pageModule, queryString;

    if (Type.isAlias(toParam)) {
      pageModule = toParam;
      queryString = "";
    } else {
      pageModule = toParam.data[0];
      queryString = $.buildPageQueryString(toParam.data[1]);
    }

    try {
      const pageModuleName = Interpreter.moduleExName(pageModule);
      const url = `/hologram/page/${pageModuleName}${queryString}`;
      const response = await fetch(url);

      if (!response.ok) {
        $.#handleFetchPageError(response.status);
      }

      const html = await response.text();
      onSuccess(html);
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        throw error;
      }

      $.#handleFetchPageError(error);
    }
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
        "X-Csrf-Token": globalThis.hologram.csrfToken,
      },
      body: Serializer.serialize($.buildCommandPayload(command), "server"),
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
        Hologram.scheduleAction(nextAction);
      }
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        throw error;
      }

      $.#failCommand(error);
    }
  }

  static #failCommand(message) {
    throw new HologramRuntimeError(`command failed: ${message}`);
  }

  static #handleFetchPageError(message) {
    throw new HologramRuntimeError(`page fetch failed: ${message}`);
  }
}

const $ = Client;

"use strict";

import App from "./app.mjs";
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

    // Sent so the server can read this tab's subscriptions from signed receipts rather
    // than from its own node's registry, which holds nothing when the command lands on
    // a node that does not hold the connection.
    const subReceipts = Array.from(
      App.subscriptionReceiptRegistry.entries.values(),
    ).map((triple) => triple.data[2]);

    return Type.map([
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
      [Type.atom("module"), module],
      [Type.atom("name"), Erlang_Maps["get/2"](Type.atom("name"), command)],
      [Type.atom("params"), Erlang_Maps["get/2"](Type.atom("params"), command)],
      [Type.atom("sub_receipts"), Type.list(subReceipts)],
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

  static buildPageRequestPayload() {
    const clientClaimedSubKeys = Array.from(
      App.subscriptionReceiptRegistry.entries.values(),
    ).map((triple) => Type.tuple([triple.data[0], triple.data[1]]));

    return Type.map([
      [Type.atom("client_claimed_sub_keys"), Type.list(clientClaimedSubKeys)],
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
    ]);
  }

  static connect(sendImmediatePing) {
    Connection.connect();
    HttpTransport.restartPing(sendImmediatePing);
  }

  // Asks the server to describe a page rather than render it, for a client that renders it itself.
  //
  // The answer is a page only when it says so: a page's middleware can answer the request instead,
  // with any status it likes including a plain 200, so the marker header rather than the status is
  // what tells the two apart. Anything that is not a page goes to onNotPage, for the caller to hand
  // to the browser - which is also where an opaque redirect lands, redirects being left to the
  // browser rather than followed here.
  static async fetchPage(toParam, onSuccess, onNotPage) {
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

      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: Serializer.serialize($.buildPageRequestPayload(), "server"),
        redirect: "manual",
      });

      // Awaited so that whatever the callback goes on to do is part of this promise. A redirect
      // answers by fetching the next page, and without the await a failure there - the hop limit
      // being one - would reject a promise nobody holds instead of reaching the caller.
      if (response.headers.get("hologram-page-data") === "true") {
        await onSuccess(await response.json());
      } else {
        await onNotPage();
      }
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
        "X-Csrf-Token": globalThis.Hologram.csrfToken,
      },
      body: Serializer.serialize($.buildCommandPayload(command), "server"),
    };

    try {
      const response = await fetch("/hologram/command", opts);

      if (!response.ok) {
        $.#failCommand(response.status);
      }

      const {
        action,
        selfEchoes: encodedSelfEchoes,
        status,
        subReceiptAdds: encodedSubReceiptAdds,
        subReceiptDrops: encodedSubReceiptDrops,
      } = await response.json();

      if (status === 0) {
        $.#failCommand(action);
      }

      const subReceiptAdds = Interpreter.evaluateJavaScriptExpression(
        encodedSubReceiptAdds,
      );

      const subReceiptDrops = Interpreter.evaluateJavaScriptExpression(
        encodedSubReceiptDrops,
      );

      App.subscriptionReceiptRegistry.merge(subReceiptAdds, subReceiptDrops);

      const nextAction = Interpreter.evaluateJavaScriptExpression(action);

      if (!Type.isNil(nextAction)) {
        Hologram.scheduleAction(nextAction);
      }

      const selfEchoes =
        Interpreter.evaluateJavaScriptExpression(encodedSelfEchoes);

      for (const action of selfEchoes.data) {
        Hologram.scheduleAction(action);
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

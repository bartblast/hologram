"use strict";

import Config from "./config.mjs";
import GlobalRegistry from "./global_registry.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Serializer from "./serializer.mjs";
import Utils from "./utils.mjs";

import {Socket} from "phoenix";

// TODO: test
export default class Client {
  static #channel = null;

  // Made public to make tests easier
  static socket = null;

  static connect() {
    Utils.runAsyncTask(() => {
      Client.socket = new Socket("/hologram", {
        encode: Client.encoder,
        longPollFallbackMs: window.location.host.startsWith("localhost")
          ? undefined
          : 3000,
      });

      Client.socket.connect();

      Client.#channel = Client.socket.channel("hologram");

      Client.#channel
        .join()
        .receive("ok", (_resp) => {
          console.debug("Hologram: connected to a server");
          GlobalRegistry.set("connected?", true);
        })
        .receive("error", (_resp) => {
          GlobalRegistry.set("connected?", false);
          throw new HologramRuntimeError("unable to connect to a server");
        })
        .receive("timeout", (_resp) => {
          GlobalRegistry.set("connected?", false);
          throw new HologramRuntimeError("unable to connect to a server");
        });

      Client.#channel.on("reload", (_payload) => document.location.reload());
    });
  }

  static encoder(msg, callback) {
    let encoded;

    if (msg.topic === "hologram") {
      const serializedPayload = Serializer.serialize(msg.payload, false, true);
      encoded = `["${msg.join_ref}","${msg.ref}","${msg.topic}","${msg.event}",${serializedPayload}]`;
    } else {
      encoded = JSON.stringify([
        msg.join_ref,
        msg.ref,
        msg.topic,
        msg.event,
        msg.payload,
      ]);
    }

    return callback(encoded);
  }

  static fetchPage(toParam, successCallback, failureCallback) {
    return Utils.runAsyncTask(() => {
      Client.#channel
        .push("page", toParam, Config.fetchPageTimeoutMs)
        .receive("ok", successCallback)
        .receive("error", failureCallback)
        .receive("timeout", failureCallback);
    });
  }

  static fetchPageBundlePath(pageModule, successCallback, failureCallback) {
    return Utils.runAsyncTask(() => {
      Client.#channel
        .push("page_bundle_path", pageModule, Config.clientFetchTimeoutMs)
        .receive("ok", successCallback)
        .receive("error", failureCallback)
        .receive("timeout", failureCallback);
    });
  }

  static isConnected() {
    return Client.socket === null ? false : Client.socket.isConnected();
  }

  static sendCommand(payload, successCallback, failureCallback) {
    Client.#channel
      .push("command", payload)
      .receive("ok", successCallback)
      .receive("error", failureCallback)
      .receive("timeout", failureCallback);
  }
}

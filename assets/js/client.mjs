"use strict";

import Config from "./config.mjs";
import JsonEncoder from "./json_encoder.mjs";

import {Socket} from "phoenix";

// TODO: test
export default class Client {
  static #channel = null;

  // Made public to make tests easier
  static socket = null;

  static async connect() {
    Client.socket = new Socket("/hologram", {
      encode: Client.encoder,
      longPollFallbackMs: 3000,
    });

    Client.socket.connect();

    Client.#channel = Client.socket.channel("hologram");

    Client.#channel
      .join()
      .receive("ok", (_resp) => {
        console.debug("Joined Hologram channel");
      })
      .receive("error", (_resp) => {
        console.error("Unable to join Hologram channel");
      });
  }

  static encoder(msg, callback) {
    return callback(
      JsonEncoder.encode([
        msg.join_ref,
        msg.ref,
        msg.topic,
        msg.event,
        msg.payload,
      ]),
    );
  }

  static async fetchPage(pagePath, successCallback, failureCallback) {
    Client.#channel
      .push("fetch_page", pagePath, Config.fetchPageTimeoutMs)
      .receive("ok", (resp) => successCallback(resp))
      .receive("error", (_resp) => {
        failureCallback();
        console.error(
          "Unable to fetch page (reason: error)",
          pagePath,
          arguments,
        );
      })
      .receive("timeout", (_resp) => {
        failureCallback();
        console.error(
          "Unable to fetch page (reason: timeout)",
          pagePath,
          arguments,
        );
      });
  }

  static isConnected() {
    return Client.socket === null ? false : Client.socket.isConnected();
  }

  static async push(event, payload, successCallback, failureCallback) {
    Client.#channel
      .push(event, payload)
      .receive("ok", (resp) => successCallback(resp))
      .receive("error", (_resp) => {
        failureCallback();
        console.error(
          "Unable to push an event to the server (reason: error)",
          arguments,
        );
      })
      .receive("timeout", (_resp) => {
        failureCallback();
        console.error(
          "Unable to push an event to the server (reason: timeout)",
          arguments,
        );
      });
  }
}

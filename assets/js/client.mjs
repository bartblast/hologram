"use strict";

import Utils from "./utils.mjs";

import {Socket} from "phoenix";

// TODO: test
export default class Client {
  static #channel = null;

  // Made public to make tests easier
  static socket = null;

  static async connect() {
    Client.socket = new Socket("/hologram", Client.encoder);
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
      Utils.serialize([
        msg.join_ref,
        msg.ref,
        msg.topic,
        msg.event,
        msg.payload,
      ]),
    );
  }

  static isConnected() {
    return Client.socket === null ? false : Client.socket.isConnected();
  }

  static async push(event, payload, successCallback, failureCallback) {
    Client.#channel
      .push(event, payload)
      .receive("ok", (_resp) => successCallback())
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

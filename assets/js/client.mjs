"use strict";

import {Socket} from "phoenix";

// TODO: test
export default class Client {
  static #channel = null;

  // Made public to make tests easier
  static socket = null;

  static async connect() {
    const socket = new Socket("/hologram");
    socket.connect();

    Client.#channel = socket.channel("hologram");

    Client.#channel
      .join()
      .receive("ok", (_resp) => {
        console.debug("Joined Hologram channel");
      })
      .receive("error", (_resp) => {
        console.error("Unable to join Hologram channel");
      });
  }

  static isConnected() {
    return Client.socket === null ? false : Client.socket.isConnected();
  }

  static async push(event, payload, callback) {
    Client.#channel
      .push(event, payload)
      .receive("ok", callback)
      .receive("error", (_resp) => {
        console.error(
          "Unable to push an event to the server (reason: error)",
          arguments,
        );
      })
      .receive("timeout", (_resp) => {
        console.error(
          "Unable to push an event to the server (reason: timeout)",
          arguments,
        );
      });
  }
}

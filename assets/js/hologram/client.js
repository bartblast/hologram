"use strict";

import { Socket } from "phoenix";

export default class Client {
  static channel = null
  static isConnected = false
  static socket = null

  // Covered implicitely in E2E tests.
  static async connect() {
    const socket = new Socket("/hologram");
    socket.connect();

    const channel = socket.channel("hologram");

    channel
      .join()
      .receive("ok", (_) => {
        Client.isConnected = true
      });

    Client.socket = socket
    Client.channel = channel
  }

  // Covered implicitely in E2E tests.
  static async pushMessage(event, payload, callback) {
    Client.channel
      .push(event, payload)
      .receive("ok", callback)
      .receive("error", (_response) => {
        console.log(`Client.pushMessage(): command error, arguments = ${JSON.stringify(arguments)}`)
      })
      .receive("timeout", (_response) => {
        console.log(`Client.pushMessage(): command timeout, arguments = ${JSON.stringify(arguments)}`)
      });
  }
}
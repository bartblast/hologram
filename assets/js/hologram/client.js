"use strict";

import { Socket } from "phoenix";
import Type from "./type"

export default class Client {
  constructor() {
    this.channel = null
    this.isConnected = false
    this.socket = null
  }

  static buildCommandPayload(targetModule, boxedName, boxedParams) {
    return {
      target_module: Type.module(targetModule.name),
      name: boxedName,
      params: boxedParams,
    }
  }

  // Tested implicitely in E2E tests.
  async connect() {
    const socket = new Socket("/hologram");
    socket.connect();

    const channel = socket.channel("hologram");

    channel
      .join()
      .receive("ok", (_) => {
        this.isConnected = true
      });

    this.socket = socket
    this.channel = channel
  }

  // Tested implicitely in E2E tests.
  async pushCommand(targetModule, boxedName, boxedParams, callback) {
    const payload = Client.buildCommandPayload(targetModule, boxedName, boxedParams)

    this.channel
      .push("command", payload)
      .receive("ok", callback)
      .receive("error", (_response) => {
        console.log("Command error")
        console.debug(arguments)
      })
      .receive("timeout", (_response) => {
        console.log("Command timeout")
        console.debug(arguments)
      });
  }
}
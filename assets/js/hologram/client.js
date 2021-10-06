"use strict";

import { Socket } from "phoenix";
import Type from "./type"

export default class Client {
  constructor(runtime) {
    this.channel = null
    this.isConnected = false
    this.runtime = runtime
    this.socket = null
  }

  static buildMessagePayload(targetModule, command, boxedParams) {
    return {
      target_module: Type.module(targetModule.name),
      command: Type.atom(command),
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
  async pushCommand(targetModule, command, boxedParams) {
    const payload = Client.buildMessagePayload(targetModule, command, boxedParams)

    this.channel
      .push("command", payload)
      .receive("ok", (response) => {
        this.runtime.handleCommandResponse(response)
      })
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
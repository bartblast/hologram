// DEFER: refactor & test

import { Socket } from "phoenix";

export default class Client {
  constructor(runtime) {
    this.channel = null
    this.isConnected = false
    this.runtime = runtime
    this.socket = null
  }

  async connect() {
    const socket = new Socket("/socket");
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

  async pushCommand(command) {
    this.channel
      .push("command", command)
      .receive("ok", (response) => {
        this.runtime.handleCommandResponse(response)
      })
      .receive("error", (_response) => {
        console.log("Command error")
        console.debug(arguments)
      })
      .receive("timeout", () => {
        console.log("Command timeout")
        console.debug(arguments)
      });
  }
}
// DEFER: refactor & test

import { Socket } from "phoenix";

export default class Client {
  constructor() {
    this.channel = null
    this.isConnected = false
    this.socket = null
  }

  static async connect() {
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
}
"use strict";

export default class Sse {
  // disconnected, connecting, connected, error
  static status = "disconnected";

  static handleOpen(_event) {
    console.log("Hologram: SSE connected");
    $.status = "connected";
  }

  static isConnected() {
    return $.status === "connected";
  }
}

const $ = Sse;

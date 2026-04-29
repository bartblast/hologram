"use strict";

export default class Sse {
  // disconnected, connecting, connected, error
  static status = "disconnected";

  static isConnected() {
    return $.status === "connected";
  }
}

const $ = Sse;

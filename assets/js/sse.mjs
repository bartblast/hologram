"use strict";

export default class Sse {
  // disconnected, connecting, connected, error
  static status = "disconnected";

  static handleError(_event) {
    // EventSource auto-reconnects on transient errors; status flips back
    // to "connected" on the next onopen.
    console.warn("Hologram: SSE error");
    $.status = "error";
  }

  static handleOpen(_event) {
    console.log("Hologram: SSE connected");
    $.status = "connected";
  }

  static isConnected() {
    return $.status === "connected";
  }
}

const $ = Sse;

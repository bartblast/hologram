"use strict";

export default class Sse {
  // disconnected, connecting, connected, error
  static status = "disconnected";

  static handleError(_event) {
    // EventSource auto-reconnects on transient errors; status flips back
    // to "connected" on the next onopen.
    $.status = "error";

    console.warn("Hologram: SSE error");
  }

  static handleMessage(event) {
    // TODO: decode the SSE event payload and dispatch the resulting
    // action through the existing client-side action pipeline.
    console.log("Hologram: SSE message", event.data);
  }

  static handleOpen(_event) {
    $.status = "connected";

    console.log("Hologram: SSE connected");
  }

  static isConnected() {
    return $.status === "connected";
  }
}

const $ = Sse;

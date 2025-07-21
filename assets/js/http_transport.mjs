"use strict";

export default class HttpTransport {
  // 30 seconds
  static PING_INTERVAL = 30_000;

  static PING_PATH = "/hologram/ping";

  static pingTimer = null;

  static isRunning() {
    return $.pingTimer !== null;
  }

  static maybeStopPing() {
    if ($.isRunning()) {
      clearInterval($.pingTimer);
      $.pingTimer = null;
    }
  }

  static ping() {
    fetch($.PING_PATH, {
      method: "HEAD",
      keepalive: true,
    }).catch((error) => {
      // Silently handle ping errors to avoid breaking the timer loop
      console.debug("Ping request failed:", error);
    });
  }

  static restartPing(sendImmediatePing = true) {
    $.maybeStopPing();
    $.startPing(sendImmediatePing);
  }

  static startPing(sendImmediatePing = true) {
    if (sendImmediatePing) {
      $.ping();
    }

    $.pingTimer = setInterval(() => {
      $.ping();
    }, $.PING_INTERVAL);
  }
}

const $ = HttpTransport;

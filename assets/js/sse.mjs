"use strict";

import Logger from "./logger.mjs";

export default class Sse {
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;

  static connect() {
    $.eventSource = new EventSource($.SSE_PATH);

    $.eventSource.onmessage = (event) =>
      Logger.debug(`SSE event: ${event.data}`);

    // Log and let the browser auto-reconnect; JS-driven reconnect lands later.
    $.eventSource.onerror = (event) => Logger.debug(`SSE error: ${event.type}`);
  }
}

const $ = Sse;

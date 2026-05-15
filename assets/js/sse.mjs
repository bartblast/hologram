"use strict";

import App from "./app.mjs";
import Logger from "./logger.mjs";

export default class Sse {
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;

  static connect() {
    const params = new URLSearchParams({instance_id: App.instanceId});
    $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

    $.eventSource.onmessage = (event) =>
      Logger.debug(`SSE event: ${event.data}`);

    // Log and let the browser auto-reconnect; JS-driven reconnect lands later.
    $.eventSource.onerror = (event) => Logger.debug(`SSE error: ${event.type}`);
  }
}

const $ = Sse;

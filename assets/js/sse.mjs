"use strict";

import Logger from "./logger.mjs";

export default class Sse {
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;

  static connect() {
    $.eventSource = new EventSource($.SSE_PATH);

    $.eventSource.onmessage = (event) =>
      Logger.debug(`SSE event: ${event.data}`);
  }
}

const $ = Sse;

"use strict";

export default class Sse {
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;

  static connect() {
    $.eventSource = new EventSource($.SSE_PATH);
  }
}

const $ = Sse;

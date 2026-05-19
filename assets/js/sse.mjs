"use strict";

import App from "./app.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import Logger from "./logger.mjs";
import Type from "./type.mjs";

export default class Sse {
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;

  static buildHandshakePayload() {
    const receipts = Array.from(
      App.subscriptionReceiptRegistry.entries.values(),
    ).map((triple) => triple.data[2]);

    return Type.map([
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
      [Type.atom("receipts"), Type.list(receipts)],
    ]);
  }

  static connect() {
    const params = new URLSearchParams({instance_id: App.instanceId});
    $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

    $.eventSource.onmessage = (event) => {
      const action = Interpreter.evaluateJavaScriptExpression(event.data);
      Hologram.scheduleAction(action);
    };

    // Log and let the browser auto-reconnect; JS-driven reconnect lands later.
    $.eventSource.onerror = (event) => Logger.debug(`SSE error: ${event.type}`);
  }
}

const $ = Sse;

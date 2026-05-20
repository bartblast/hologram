"use strict";

import App from "./app.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import Logger from "./logger.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Sse {
  static HANDSHAKE_PATH = "/hologram/sse/handshake";
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

  static async connect() {
    try {
      const preHandshakeReceiptCount =
        App.subscriptionReceiptRegistry.entries.size;

      const response = await fetch($.HANDSHAKE_PATH, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: Serializer.serialize($.buildHandshakePayload(), "server"),
      });

      if (!response.ok) {
        Logger.debug(`SSE handshake error: ${response.status}`);
        return;
      }

      const {handshakeId, refreshedReceipts: encodedRefreshed} =
        await response.json();

      const refreshed =
        Interpreter.evaluateJavaScriptExpression(encodedRefreshed);

      if (preHandshakeReceiptCount > 0 && refreshed.data.length === 0) {
        window.location.reload();
        return;
      }

      App.subscriptionReceiptRegistry.merge(refreshed, Type.list());

      const params = new URLSearchParams({
        instance_id: App.instanceId,
        handshake_id: handshakeId,
      });

      $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

      $.eventSource.onmessage = (event) => {
        const action = Interpreter.evaluateJavaScriptExpression(event.data);
        Hologram.scheduleAction(action);
      };

      // Log and let the browser auto-reconnect; JS-driven reconnect lands later.
      $.eventSource.onerror = (event) =>
        Logger.debug(`SSE error: ${event.type}`);
    } catch (error) {
      Logger.debug(`SSE handshake error: ${error}`);
    }
  }
}

const $ = Sse;

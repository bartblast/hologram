"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import Logger from "./logger.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Sse {
  static BASE_RECONNECT_DELAY = 250;
  static HANDSHAKE_PATH = "/hologram/sse/handshake";
  static MAX_RECONNECT_DELAY = 5_000;
  static RECONNECT_BACKOFF_FACTOR = 2;
  static RECONNECT_JITTER = 0.25;
  static SSE_PATH = "/hologram/sse";

  static eventSource = null;
  static reconnectAttempts = 0;

  // Exponential backoff with ±RECONNECT_JITTER noise. Mirrors the established
  // pattern in `Hologram.Connection` so consecutive SSE reconnect failures
  // don't hammer the handshake endpoint.
  static computeReconnectDelay(attempts) {
    const baseDelay = Math.min(
      $.BASE_RECONNECT_DELAY *
        Math.pow($.RECONNECT_BACKOFF_FACTOR, attempts - 1),
      $.MAX_RECONNECT_DELAY,
    );

    const jitterRange = baseDelay * $.RECONNECT_JITTER;

    return baseDelay + (Math.random() * 2 - 1) * jitterRange;
  }

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
    // At most one stream is live at a time. Whatever is in the slot is closed before
    // this attempt starts, so a stream this client has moved on from is never left
    // open, reconnecting natively, and firing handlers of its own.
    $.eventSource?.close();
    $.eventSource = null;

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
        $.scheduleReconnect();
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

      const eventSource = new EventSource(`${$.SSE_PATH}?${params}`);
      $.eventSource = eventSource;

      eventSource.addEventListener("action", (event) => {
        const action = Interpreter.evaluateJavaScriptExpression(event.data);
        const target = Erlang_Maps["get/2"](Type.atom("target"), action);

        // Hologram realtime is fire-and-forget: silently drop actions
        // targeting cids that are not mounted on this client. Keeps the
        // dispatcher's strict contract intact for command responses (where
        // a missing cid is a real bug worth surfacing).
        if (!ComponentRegistry.isCidRegistered(target)) {
          return;
        }

        Hologram.scheduleAction(action);
      });

      eventSource.addEventListener("add_sub_receipts", (event) => {
        const receipts = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(receipts, Type.list());
      });

      eventSource.addEventListener("broadcast", (event) => {
        const decoded = Interpreter.evaluateJavaScriptExpression(event.data);
        const [actionName, params, cidsList] = decoded.data;

        for (const cid of cidsList.data) {
          if (!ComponentRegistry.isCidRegistered(cid)) continue;

          const action = Type.actionStruct({
            name: actionName,
            params: params,
            target: cid,
          });

          Hologram.scheduleAction(action);
        }
      });

      eventSource.addEventListener("drop_sub_receipts", (event) => {
        const keys = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.purge(keys);
      });

      eventSource.addEventListener("refresh_sub_receipts", (event) => {
        const refreshed = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      });

      eventSource.onopen = () => {
        if (!$.isCurrentStream(eventSource)) {
          return;
        }

        $.reconnectAttempts = 0;
        GlobalRegistry.set("sseConnected?", true);
      };

      // JS-driven reconnect: native EventSource auto-reconnect would re-use
      // the original URL with the now-stale single-use handshake_id and
      // produce a 4xx loop. Close the failed connection and re-run the
      // handshake protocol from scratch after an exponential backoff delay.
      // No retry cap: the receipt-expiry path inside `connect()` handles the
      // "give up and reload" case organically once stored receipts age out.
      eventSource.onerror = (event) => {
        if (!$.isCurrentStream(eventSource)) {
          return;
        }

        Logger.debug(`SSE error: ${event.type}`);
        GlobalRegistry.set("sseConnected?", false);

        eventSource.close();
        $.eventSource = null;

        $.scheduleReconnect();
      };
    } catch (error) {
      Logger.debug(`SSE handshake error: ${error}`);
      $.scheduleReconnect();
    }
  }

  // Whether the given stream is the one this client is currently running.
  //
  // Closing a stream does not unqueue the events it has already dispatched, so a
  // handler can run for a stream that has since been replaced. Such a handler decides
  // nothing: acting on it would let a stream the client has moved on from tear down or
  // vouch for the live one.
  static isCurrentStream(eventSource) {
    return eventSource === $.eventSource;
  }

  // Bump the failure counter and re-run the handshake protocol from scratch
  // after an exponential backoff delay. Shared by the handshake-failure paths
  // and the post-open EventSource onerror handler so a failure anywhere in the
  // connect lifecycle backs off identically instead of leaving realtime down.
  static scheduleReconnect() {
    $.reconnectAttempts++;
    const delay = $.computeReconnectDelay($.reconnectAttempts);

    setTimeout(() => $.connect(), delay);
  }
}

const $ = Sse;

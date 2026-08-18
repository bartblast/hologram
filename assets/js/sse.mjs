"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Deltas from "./deltas.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
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

  // How long a stream has to last before the client forgets the failures that preceded
  // it. Opening is not enough: the server sends the 200 before the work that can kill
  // the stream runs, so a doomed connection still opens.
  //
  // The only hard requirement is that it exceed the time a doomed stream takes to die,
  // which is milliseconds - the death follows the 200 in the same request. Everything
  // above that is policy, and this is set to MAX_RECONNECT_DELAY's 5 s for one
  // property: a stream that dies sooner than the longest retry delay can never clear
  // the count, so a connection that keeps dying right after opening climbs to the
  // ceiling and stays there rather than retrying at the floor forever. The two are
  // kept as separate numbers because they answer separate questions - how hard may we
  // retry, and how long until we trust - and should be free to move apart.
  static STABLE_CONNECTION_MS = 5_000;

  static eventSource = null;
  static reconnectAttempts = 0;
  static renderScheduled = false;
  static stabilityTimer = null;

  // The place in the log this client has been brought up to, kept across reconnects rather than
  // with the stream that delivered it: the listeners are registered again on every new stream,
  // and a place held with them would be dropped exactly when the client needs it to say what it
  // already has. What it is made of is the server's business - it is kept and handed back.
  static syncCursor = null;

  // What the client tells the server so it can be kept up to date: the wire format this bundle
  // speaks, the model it was built against, and the page it is on. The first two are baked into
  // the bundle rather than read from the page, because what they answer is whether THIS
  // JavaScript is stale - a value the current server put in the page would always agree with it.
  //
  // A bundle built before any of this existed carries no constants and sends no greeting, which
  // is what leaves it with the realtime stream it already had.
  static buildSyncGreeting(pageModule) {
    const sync = globalThis.Hologram.sync;

    if (!sync || pageModule === null) {
      return {};
    }

    const greeting = {
      model_hash: sync.modelHash,
      page: Interpreter.moduleExName(pageModule),
      protocol_version: sync.protocolVersion,
    };

    // A client arriving for the first time has no place to name, and asks for everything it may
    // see. One coming back names where it got to, and is told only what moved since.
    if ($.syncCursor !== null) {
      greeting.cursor = $.syncCursor;
    }

    return greeting;
  }

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
        ...$.buildSyncGreeting(Hologram.currentPageModule()),
      });

      $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

      $.eventSource.addEventListener("action", (event) => {
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

      $.eventSource.addEventListener("add_sub_receipts", (event) => {
        const receipts = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(receipts, Type.list());
      });

      $.eventSource.addEventListener("broadcast", (event) => {
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

      $.eventSource.addEventListener("drop_sub_receipts", (event) => {
        const keys = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.purge(keys);
      });

      $.eventSource.addEventListener("refresh_sub_receipts", (event) => {
        const refreshed = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      });

      // The four sync kinds carry JSON rather than the JavaScript every other kind on this
      // stream is written in - a delta holds the values a database stores, and spelling those as
      // source costs ten times the bytes on the payload a whole-app fill is mostly made of.
      $.eventSource.addEventListener("sync_deltas", (event) => {
        const frame = JSON.parse(event.data);

        Deltas.apply(frame.deltas);

        // Mid-fill the server hands over no place, because a client holding part of a pot could
        // not honour the claim one makes. Keeping the last place it DID name is what lets a
        // client cut off mid-fill come back asking for everything again rather than for the
        // little that changed since.
        if (frame.cursor !== null) {
          $.syncCursor = frame.cursor;
        }

        $.scheduleRender();
      });

      $.eventSource.addEventListener("synced", (event) => {
        const frame = JSON.parse(event.data);

        LocalDatabase.markSynced(frame.scope);

        // What a query answers can change the moment a scope is complete - a count that was
        // reading the server's number starts counting rows - so the marker is a reason to
        // render like any frame is.
        $.scheduleRender();
      });

      $.eventSource.onopen = () => {
        GlobalRegistry.set("sseConnected?", true);

        // Opening reports liveness. Clearing the failure count is a separate judgement
        // the stream has to earn by lasting, so one that opens and dies still counts as
        // a failed attempt and the delay after it grows.
        $.stabilityTimer = setTimeout(() => {
          $.reconnectAttempts = 0;
        }, $.STABLE_CONNECTION_MS);
      };

      // JS-driven reconnect: native EventSource auto-reconnect would re-use
      // the original URL with the now-stale single-use handshake_id and
      // produce a 4xx loop. Close the failed connection and re-run the
      // handshake protocol from scratch after an exponential backoff delay.
      // No retry cap: the receipt-expiry path inside `connect()` handles the
      // "give up and reload" case organically once stored receipts age out.
      $.eventSource.onerror = (event) => {
        clearTimeout($.stabilityTimer);

        Logger.debug(`SSE error: ${event.type}`);
        GlobalRegistry.set("sseConnected?", false);
        $.eventSource.close();

        $.scheduleReconnect();
      };
    } catch (error) {
      Logger.debug(`SSE handshake error: ${error}`);
      $.scheduleReconnect();
    }
  }

  // One render per animation frame, however many frames arrive in between: a fill lands as a
  // burst, and a repaint per frame would be work nobody sees.
  //
  // Scheduled rather than run here, always. Rendering reconciles, attaching listeners as it
  // goes, and an action dispatched by one of those renders again - a repaint started from inside
  // this handler would be a repaint started from inside a repaint.
  static scheduleRender() {
    if ($.renderScheduled) {
      return;
    }

    $.renderScheduled = true;

    window.requestAnimationFrame(() => {
      $.renderScheduled = false;
      Hologram.render();
    });
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

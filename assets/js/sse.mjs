"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import LiveReload from "./live_reload.mjs";
import Logger from "./logger.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Sse {
  static BASE_RECONNECT_DELAY = 250;
  static HANDSHAKE_PATH = "/hologram/sse/handshake";

  // A stream with no heartbeat for this many intervals is dead. The real bound is one
  // interval plus the heartbeat's delivery delay (network latency, and whatever the
  // server's pump is writing ahead of it), and the delay is a property of the
  // deployment, not of Hologram. Two is policy: the first heartbeat may be late, the
  // second missing one is the verdict.
  static HEARTBEAT_TIMEOUT_INTERVALS = 2;

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
  static heartbeatIntervalMs = null;
  static heartbeatTimer = null;

  // Whether the page has asked for the stream, which it does once it is first mounted.
  static isStarted = false;

  // Whether the page has been left: from pagehide until the browser brings the page back
  // from its back/forward cache, if it ever does.
  static isSuspended = false;

  static reconnectAttempts = 0;
  static reconnectTimer = null;

  // Tells apart a connect() run that suspend() has overtaken from the current one: a
  // handshake in flight when the page is left must neither open a stream nor schedule a retry.
  static runId = 0;

  static stabilityTimer = null;

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

  // Browsers never surface a dead stream that was not closed (a killed HTTP/2 stream
  // on Bandit, a proxy dropping the upstream, a NAT forgetting the connection), so the
  // client keeps its own clock: every heartbeat pushes the deadline, and a missed one
  // ends the stream the way a browser-reported error does.
  static armHeartbeatWatchdog() {
    clearTimeout($.heartbeatTimer);

    $.heartbeatTimer = setTimeout(
      () => $.handleStreamLoss("heartbeat timeout"),
      $.heartbeatIntervalMs * $.HEARTBEAT_TIMEOUT_INTERVALS,
    );
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
    const runId = $.runId;
    const isStale = () => runId !== $.runId;

    try {
      const preHandshakeReceiptCount =
        App.subscriptionReceiptRegistry.entries.size;

      const response = await fetch($.HANDSHAKE_PATH, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: Serializer.serialize($.buildHandshakePayload(), "server"),
      });

      if (isStale()) return;

      if (!response.ok) {
        Logger.debug(`SSE handshake error: ${response.status}`);
        $.scheduleReconnect();
        return;
      }

      const {
        handshakeId,
        heartbeatIntervalMs,
        refreshedReceipts: encodedRefreshed,
      } = await response.json();

      if (isStale()) return;

      const refreshed =
        Interpreter.evaluateJavaScriptExpression(encodedRefreshed);

      if (preHandshakeReceiptCount > 0 && refreshed.data.length === 0) {
        window.location.reload();
        return;
      }

      App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      $.heartbeatIntervalMs = heartbeatIntervalMs;

      const params = new URLSearchParams({
        instance_id: App.instanceId,
        handshake_id: handshakeId,
      });

      $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

      // An action or a broadcast arrives as JSON holding the encoded term and the digests of the
      // chunks the struct types in it need, which are loaded before the action runs (see
      // Hologram.schedulePushedAction).
      $.eventSource.addEventListener("action", (event) => {
        const {action: encodedAction, chunks} = JSON.parse(event.data);
        const action = Interpreter.evaluateJavaScriptExpression(encodedAction);
        const target = Erlang_Maps["get/2"](Type.atom("target"), action);

        // Hologram realtime is fire-and-forget: silently drop actions
        // targeting cids that are not mounted on this client, as Client.sendCommand
        // drops a reply's self echoes. Keeps the dispatcher's strict contract
        // intact for a reply's next action (where a missing cid is a real bug
        // worth surfacing).
        if (!ComponentRegistry.isCidRegistered(target)) {
          return;
        }

        Hologram.schedulePushedAction(action, chunks);
      });

      $.eventSource.addEventListener("add_sub_receipts", (event) => {
        const receipts = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(receipts, Type.list());
      });

      $.eventSource.addEventListener("broadcast", (event) => {
        const {chunks, data} = JSON.parse(event.data);
        const decoded = Interpreter.evaluateJavaScriptExpression(data);
        const [actionName, params, cidsList] = decoded.data;

        for (const cid of cidsList.data) {
          if (!ComponentRegistry.isCidRegistered(cid)) continue;

          const action = Type.actionStruct({
            name: actionName,
            params: params,
            target: cid,
          });

          Hologram.schedulePushedAction(action, chunks);
        }
      });

      // Live reload events carry plain JSON, when they carry anything, rather than encoded
      // terms: the server builds them outside any page, from a compile error and a list of
      // page names.
      $.eventSource.addEventListener("compilation_error", (event) => {
        LiveReload.showErrorOverlay(JSON.parse(event.data));
      });

      $.eventSource.addEventListener("compiled", () => {
        LiveReload.hideErrorOverlay();
      });

      $.eventSource.addEventListener("css_changed", (event) => {
        LiveReload.swapStylesheets(JSON.parse(event.data));
      });

      $.eventSource.addEventListener("drop_sub_receipts", (event) => {
        const keys = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.purge(keys);
      });

      $.eventSource.addEventListener("heartbeat", () => {
        $.armHeartbeatWatchdog();
      });

      $.eventSource.addEventListener("refresh_sub_receipts", (event) => {
        const refreshed = Interpreter.evaluateJavaScriptExpression(event.data);
        App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      });

      $.eventSource.addEventListener("reload", (event) => {
        LiveReload.handleReload(JSON.parse(event.data), Hologram.pageModule());
      });

      $.eventSource.onopen = () => {
        GlobalRegistry.set("sseConnected?", true);
        $.armHeartbeatWatchdog();

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
        $.handleStreamLoss(event.type);
      };
    } catch (error) {
      // Leaving the page aborts a handshake in flight.
      if (isStale()) return;

      Logger.debug(`SSE handshake error: ${error}`);
      $.scheduleReconnect();
    }
  }

  // A stream is over whether the browser reported it or the heartbeat watchdog did:
  // stop trusting it, close it, and re-run the handshake protocol after a backoff.
  static handleStreamLoss(reason) {
    clearTimeout($.heartbeatTimer);
    clearTimeout($.stabilityTimer);

    Logger.debug(`SSE stream lost: ${reason}`);
    GlobalRegistry.set("sseConnected?", false);
    $.eventSource.close();

    $.scheduleReconnect();
  }

  // Reopens the stream on a page the browser brought back from its back/forward cache, where
  // suspend() closed it. A page left before its first mount has nothing to reopen: start()
  // opens the stream once the page is mounted.
  static resume() {
    if (!$.isSuspended) return;

    $.isSuspended = false;

    if ($.isStarted) {
      $.connect();
    }
  }

  // Bump the failure counter and re-run the handshake protocol from scratch
  // after an exponential backoff delay. Shared by the handshake-failure paths
  // and the post-open EventSource onerror handler so a failure anywhere in the
  // connect lifecycle backs off identically instead of leaving realtime down.
  static scheduleReconnect() {
    $.reconnectAttempts++;
    const delay = $.computeReconnectDelay($.reconnectAttempts);

    $.reconnectTimer = setTimeout(() => $.connect(), delay);
  }

  // Opens the stream the first time it is called, and does nothing after that: the page asks
  // on every mount, while connect() and its retries keep the one stream alive from then on.
  // Asking again while the first handshake is still in flight or being retried would start a
  // second stream next to the first.
  static start() {
    if ($.isStarted) return;

    $.isStarted = true;

    if (!$.isSuspended) {
      $.connect();
    }
  }

  // Closes the stream when the page is left (pagehide), whether the document is being
  // destroyed or put into the back/forward cache. Chrome keeps the stream of a destroyed
  // document open (https://issues.chromium.org/issues/358538891), and over HTTP/1.1 six such
  // streams use up the connections the browser allows per origin, so every further request
  // to it stalls. Everything that could reopen the stream is cancelled along with it: the
  // timers, and a handshake in flight (see runId).
  static suspend() {
    $.isSuspended = true;
    $.runId++;

    clearTimeout($.heartbeatTimer);
    clearTimeout($.reconnectTimer);
    clearTimeout($.stabilityTimer);

    $.reconnectAttempts = 0;

    if ($.eventSource !== null) {
      $.eventSource.close();
    }

    GlobalRegistry.set("sseConnected?", false);
  }
}

const $ = Sse;

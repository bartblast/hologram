"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Deserializer from "./deserializer.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
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
  static reconnectAttempts = 0;

  // The pending retry after a stream died, held so a deliberate restart can call it off - the same
  // bookkeeping `Connection` keeps for the websocket's.
  static reconnectTimer = null;
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

      const {
        handshakeId,
        heartbeatIntervalMs,
        refreshedReceipts: serializedRefreshed,
      } = await response.json();

      const refreshed = Deserializer.deserialize(serializedRefreshed);

      if (preHandshakeReceiptCount > 0 && refreshed.data.length === 0) {
        window.location.reload();
        return;
      }

      App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      $.heartbeatIntervalMs = heartbeatIntervalMs;

      // An app without a data model greets with nothing, the way a tab that does not lead does.
      const greeting =
        Hologram.dataLayer?.buildStreamGreeting(Hologram.pageModule()) ?? {};

      const params = new URLSearchParams({
        instance_id: App.instanceId,
        handshake_id: handshakeId,
        ...greeting,
      });

      // Whatever was here goes first. Two connects can be in flight at once - a retry scheduled
      // by a dying stream, and a deliberate restart under a new identity - and the second to
      // arrive would otherwise leave the first's stream open with nothing referring to it,
      // delivering every action and every frame a second time.
      $.eventSource?.close();

      $.eventSource = new EventSource(`${$.SSE_PATH}?${params}`);

      // An action or a broadcast arrives as JSON holding the serialized term and the digests of the
      // chunks the struct types in it need, which are loaded before the action runs (see
      // Hologram.schedulePushedAction). The other events carry the serialized term alone.
      $.eventSource.addEventListener("action", (event) => {
        const {action: serializedAction, chunks} = JSON.parse(event.data);
        const action = Deserializer.deserialize(serializedAction);
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
        const receipts = Deserializer.deserialize(event.data);
        App.subscriptionReceiptRegistry.merge(receipts, Type.list());
      });

      $.eventSource.addEventListener("broadcast", (event) => {
        const {chunks, data} = JSON.parse(event.data);
        const envelope = Deserializer.deserialize(data);
        const [actionName, params, cidsList] = envelope.data;

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

      // Live reload events carry plain JSON, when they carry anything, rather than serialized
      // terms: the server builds them outside any page, from a compile error and a list of
      // page names.
      $.eventSource.addEventListener("compilation_error", (event) => {
        LiveReload.showErrorOverlay(JSON.parse(event.data));
      });

      $.eventSource.addEventListener("compiled", () => {
        LiveReload.hideErrorOverlay();
      });

      $.eventSource.addEventListener("drop_sub_receipts", (event) => {
        const keys = Deserializer.deserialize(event.data);
        App.subscriptionReceiptRegistry.purge(keys);
      });

      $.eventSource.addEventListener("heartbeat", () => {
        $.armHeartbeatWatchdog();
      });

      $.eventSource.addEventListener("refresh_sub_receipts", (event) => {
        const refreshed = Deserializer.deserialize(event.data);
        App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      });

      Hologram.dataLayer?.listenToStream($.eventSource);

      $.eventSource.addEventListener("reload", (event) => {
        LiveReload.handleReload(JSON.parse(event.data), Hologram.pageModule());
      });

      $.eventSource.onopen = () => {
        GlobalRegistry.set("sseConnected?", true);
        $.armHeartbeatWatchdog();

        // The one signal that actually means the network is worth trying again (see
        // DataLayer.streamOpened).
        Hologram.dataLayer?.streamOpened();

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

  // Drops the stream and opens a new one, for a client whose greeting has changed since it
  // connected - a replica whose identity was refused and replaced is the case that needs it. The
  // server decides what a stream serves from what it was greeted with, so a client that becomes
  // somebody else mid-page has to say so, and the only place it says anything is the connect.
  //
  // Deliberate rather than a failure, which is why the attempt counter is left alone and no backoff
  // applies: nothing went wrong, and the delay a failing stream has earned is not this one's to
  // serve.
  // Answers the connect's own promise, so a caller that wants to know the new stream is up can
  // wait for it. Nothing in the framework does - a replaced stream is opened and forgotten.
  static reconnect() {
    // A retry the dying stream had already scheduled is called off, or it would open a second
    // stream on top of this one a moment later.
    clearTimeout($.reconnectTimer);
    $.reconnectTimer = null;

    $.eventSource?.close();
    $.eventSource = null;

    return $.connect();
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
}

const $ = Sse;

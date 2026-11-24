"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Deserializer from "./deserializer.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import IdentityTracker from "./identity_tracker.mjs";
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

  // How many answered handshakes can put off a reload for expired receipts while a tab still holds
  // unsent writes only in memory. On the reconnect backoff that's a little over 40 seconds, longer
  // than one send's deadline. It's a limit because a write the server keeps refusing never leaves,
  // and the tab has no live stream until it reloads.
  static MAX_RELOAD_DEFERRALS = 12;

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

  // The identity period of the last handshake. Once it has ended, the subscriptions this tab holds
  // were authorized for an identity it has left, and the server is right to refuse them.
  static handshakePeriod = null;

  static reconnectAttempts = 0;

  // How many times a refused tab asks for an identity after the signed-in user changed (see
  // askForReplica). With the reconnect delays they span about 13 seconds.
  static MAX_REPLICA_ASKS = 6;

  // Tells apart the latest askForReplica() from one it replaced.
  static replicaAskId = 0;

  // Whether an askForReplica() is under way, or was when the page was left.
  static isAskingForReplica = false;

  // How many handshakes in a row have put off a reload (see MAX_RELOAD_DEFERRALS).
  static reloadDeferrals = 0;

  // The pending retry after a stream died, held so a deliberate restart can call it off - the same
  // bookkeeping `Connection` keeps for the websocket's.
  static reconnectTimer = null;

  // Tells apart a connect() run that suspend() or reconnect() has overtaken from the current one: a
  // handshake in flight when the page is left must neither open a stream nor schedule a retry, and
  // one a deliberate restart replaced would close the stream that restart opens.
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

    const entries = [
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
      [Type.atom("receipts"), Type.list(receipts)],
    ];

    const presented = Hologram.dataLayer?.replicaToReplace();

    if (presented) {
      entries.push(
        [Type.atom("replica_id"), Type.bitstring(presented.id ?? "")],
        [Type.atom("replica_token"), Type.bitstring(presented.token ?? "")],
      );
    }

    return Type.map(entries);
  }

  // Asks for an identity again after the signed-in user changed, for a tab the server refused one.
  // The stream hears of a sign-in before the response carrying the new session cookie reaches the
  // browser, so the first answers can still be refusals under the old cookie. The open stream is
  // left alone while asking: the server has already moved it to the new user, and a stream opened
  // under the old cookie would serve the previous user's rows. It is replaced once a pair arrives,
  // since its greeting names the identity it serves.
  static async askForReplica() {
    const askId = ++$.replicaAskId;

    const isOver = () =>
      askId !== $.replicaAskId || !Hologram.dataLayer?.replicaToReplace();

    $.isAskingForReplica = true;

    try {
      for (let attempt = 1; attempt <= $.MAX_REPLICA_ASKS; attempt++) {
        await new Promise((resolve) =>
          setTimeout(resolve, $.computeReconnectDelay(attempt)),
        );

        if (isOver()) return;

        // A request that never answers is given up on, or it would hold back the asks after it.
        const controller = new AbortController();

        const deadline = setTimeout(
          () => controller.abort(),
          Config.mutationTimeoutMs,
        );

        try {
          const response = await fetch($.HANDSHAKE_PATH, {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: Serializer.serialize($.buildHandshakePayload(), "server"),
            signal: controller.signal,
          });

          if (!response.ok) continue;

          const {replica} = await response.json();

          if (isOver()) return;

          if (replica) {
            Hologram.dataLayer.takeReplica(replica);

            return $.reconnect();
          }
        } catch {
          // No answer is one more try gone, as a refusal is.
        } finally {
          clearTimeout(deadline);
        }
      }
    } finally {
      // An ask the page's leaving cut short stays marked, so resume() starts another.
      if (askId === $.replicaAskId) $.isAskingForReplica = false;
    }
  }

  // Closes the stream there is, and stops the clocks it was keeping: the heartbeat watchdog, which
  // would otherwise end whatever stream stands in its place at its deadline, and the stability
  // timer, which would clear the failure count on the strength of a stream that is gone. And the
  // page no longer says it is connected until the stream that replaces it opens.
  static closeStream() {
    clearTimeout($.heartbeatTimer);
    clearTimeout($.stabilityTimer);

    $.eventSource?.close();

    GlobalRegistry.set("sseConnected?", false);
  }

  static async connect() {
    const runId = $.runId;
    const isStale = () => runId !== $.runId;

    // A tab with no identity to send under, waiting for one or refused one, holds its writes until
    // a handshake brings it. One holding unsent writes may have to put off a reload over this
    // answer, and one that already has needs the answer to decide it. For those, a handshake that
    // never answers is given up on and tried again.
    const controller = new AbortController();

    const presented = Hologram.dataLayer?.replicaToReplace();

    const deadline =
      presented ||
      Hologram.dataLayer?.holdsUnsentWrites() ||
      $.reloadDeferrals > 0
        ? setTimeout(() => controller.abort(), Config.mutationTimeoutMs)
        : null;

    try {
      const presentedReceipts = new Map(
        App.subscriptionReceiptRegistry.entries,
      );

      const response = await fetch($.HANDSHAKE_PATH, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: Serializer.serialize($.buildHandshakePayload(), "server"),
        signal: controller.signal,
      });

      if (isStale()) return;

      if (!response.ok) {
        Logger.debug(`SSE handshake error: ${response.status}`);
        $.scheduleReconnect();
        return;
      }

      const {
        actorEntityId,
        actorUserId,
        handshakeId,
        heartbeatIntervalMs,
        identityTag,
        refreshedReceipts: serializedRefreshed,
        replica,
        replicaRefused,
        sessionReplica,
      } = await response.json();

      if (isStale()) return;

      // Before the receipts are judged: a tab the handshake moves to another user moves its
      // identity period, so the previous user's receipts the server refused are dropped rather than
      // taken for receipts that expired. A cookie behind the identity the tab follows opens no
      // stream, records no period and changes no receipts: it isn't the session the tab is in, and
      // the follow opens a new stream once the server says who is (see DataLayer.takeHandshake).
      const opens =
        Hologram.dataLayer?.takeHandshake({
          actorEntityId,
          actorUserId,
          identityTag,
          replica: sessionReplica,
        }) ?? true;

      // The follow can have opened a new stream already.
      if (isStale() || !opens) return;

      const refreshed = Deserializer.deserialize(serializedRefreshed);

      // Before the greeting, so the stream opens under the identity this tab will send with. The
      // sender is woken here rather than when the stream opens: a proxy can block the stream while
      // writes still get through.
      const sending = Hologram.dataLayer?.takeReplica(
        replica,
        replicaRefused === true,
        presented?.id,
      );

      if ($.#hasIdentityMoved()) {
        $.#dropRefusedReceipts(presentedReceipts, refreshed);
      } else if (presentedReceipts.size > 0 && refreshed.data.length === 0) {
        // A write held for that identity exists only in this tab's memory, so it goes out before
        // the page does. A sender that failed says so in the check below.
        await sending?.catch(() => {});

        if (isStale()) return;

        if (
          Hologram.dataLayer?.holdsUnsentWrites() &&
          $.reloadDeferrals < $.MAX_RELOAD_DEFERRALS
        ) {
          $.reloadDeferrals++;
          $.scheduleReconnect();
          return;
        }

        window.location.reload();
        return;
      }

      $.handshakePeriod = IdentityTracker.period;
      $.reloadDeferrals = 0;

      App.subscriptionReceiptRegistry.merge(refreshed, Type.list());
      $.heartbeatIntervalMs = heartbeatIntervalMs;

      // Still waiting after an answer: it came from a node of an older build during a deploy, or
      // from a handshake that started before this tab asked. Writes are held until one brings the
      // identity, so this asks again.
      if (Hologram.dataLayer?.wantsReplica()) {
        $.scheduleReconnect();
        return;
      }

      // An app without a data model greets with nothing, the way a tab that does not lead does.
      const greeting =
        Hologram.dataLayer?.buildStreamGreeting(Hologram.pageModule()) ?? {};

      const params = new URLSearchParams({
        instance_id: App.instanceId,
        handshake_id: handshakeId,
        ...greeting,
      });

      // Whatever was here goes first. Two connects can be in flight at once, like a page's first
      // one and a retry a dying stream scheduled, and the second to arrive would otherwise leave
      // the first's stream open with nothing referring to it, delivering every action and every
      // frame a second time.
      $.closeStream();

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

      $.eventSource.addEventListener("css_changed", (event) => {
        LiveReload.swapStylesheets(JSON.parse(event.data));
      });

      $.eventSource.addEventListener("drop_sub_receipts", (event) => {
        const keys = Deserializer.deserialize(event.data);
        App.subscriptionReceiptRegistry.purge(keys);
      });

      $.eventSource.addEventListener("heartbeat", () => {
        $.armHeartbeatWatchdog();

        // The one wake-up that comes with nothing happening (see DataLayer.streamBeat).
        Hologram.dataLayer?.streamBeat();
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
      // Leaving the page aborts a handshake in flight.
      if (isStale()) return;

      Logger.debug(`SSE handshake error: ${error}`);
      $.scheduleReconnect();
    } finally {
      clearTimeout(deadline);
    }
  }

  // A stream is over whether the browser reported it or the heartbeat watchdog did:
  // stop trusting it, close it, and re-run the handshake protocol after a backoff.
  static handleStreamLoss(reason) {
    Logger.debug(`SSE stream lost: ${reason}`);

    $.closeStream();
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
  //
  // A page that has been left opens no stream: resume() connects, with the greeting of that
  // moment, if the browser brings the page back.
  static reconnect() {
    if ($.isSuspended) return Promise.resolve();

    // A retry the dying stream had already scheduled is called off, or it would open a second
    // stream on top of this one a moment later.
    clearTimeout($.reconnectTimer);
    $.reconnectTimer = null;

    // So is a handshake still on its way: it was made with the session as it was, and answering
    // last it would replace this stream with its own.
    $.runId++;

    $.closeStream();
    $.eventSource = null;
    $.runId++;

    return $.connect();
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

    // The new cookie may still be on its way, and this handshake alone could be refused under the
    // old one. The ask waits out a delay first, so the handshake goes before it.
    if ($.isAskingForReplica) {
      $.askForReplica();
    }
  }

  // Bump the failure counter and re-run the handshake protocol from scratch
  // after an exponential backoff delay. Shared by the handshake-failure paths
  // and the post-open EventSource onerror handler so a failure anywhere in the
  // connect lifecycle backs off identically instead of leaving realtime down.
  static scheduleReconnect() {
    // Overlapping handshakes can each ask for a retry. One timer is kept, so that suspend() and
    // reconnect() can call it off.
    clearTimeout($.reconnectTimer);

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
  // timers, a handshake in flight (see runId), and an ask for an identity (see replicaAskId).
  static suspend() {
    $.isSuspended = true;
    $.replicaAskId++;
    $.runId++;

    clearTimeout($.reconnectTimer);

    $.reconnectAttempts = 0;
    $.reloadDeferrals = 0;

    $.closeStream();
  }

  // Leaves any receipt added while the handshake was under way, which it didn't present - one
  // that replaced a presented receipt under the same key too.
  static #dropRefusedReceipts(presentedReceipts, refreshed) {
    const refreshedKeys = new Set(
      refreshed.data.map((triple) =>
        Type.encodeMapKey(Type.tuple(triple.data.slice(0, 2))),
      ),
    );

    for (const [key, receipt] of presentedReceipts) {
      if (
        !refreshedKeys.has(key) &&
        App.subscriptionReceiptRegistry.entries.get(key) === receipt
      ) {
        App.subscriptionReceiptRegistry.entries.delete(key);
      }
    }
  }

  static #hasIdentityMoved() {
    return (
      IdentityTracker.period !==
      ($.handshakePeriod ?? IdentityTracker.documentPeriod)
    );
  }
}

const $ = Sse;

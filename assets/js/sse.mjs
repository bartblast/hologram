"use strict";

import App from "./app.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Batches from "./batches.mjs";
import Deltas from "./deltas.mjs";
import Durability from "./durability.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";
import Serializer from "./serializer.mjs";
import Tabs from "./tabs.mjs";
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

  // The pending retry after a stream died, held so a deliberate restart can call it off - the same
  // bookkeeping `Connection` keeps for the websocket's.
  static reconnectTimer = null;
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

    const pageModuleName = Interpreter.moduleExName(pageModule);

    // The page this client greeted with - the one whose rows the server declares complete at the
    // "page" scope, which is a narrower promise than "all" and arrives sooner. Navigation moves
    // the current page and leaves this one behind, since only what the connect asked for is
    // covered by that scope.
    GlobalRegistry.set("connectPageModule", pageModuleName);

    const greeting = {
      model_hash: sync.modelHash,
      page: pageModuleName,
      protocol_version: sync.protocolVersion,
    };

    // A client arriving for the first time has no place to name, and asks for everything it may
    // see. One coming back names where it got to, and is told only what moved since.
    if ($.syncCursor !== null) {
      greeting.cursor = $.syncCursor;
    }

    // The identity this browser presents - the pair it remembered from an earlier page load, or
    // the current page's when it remembers none. This client invents neither half, the same as
    // when it sends a batch. What it buys on this stream is being told how far its own writes are
    // in what a frame carries, which is what stops it applying them a second time.
    //
    // Both or neither: an id is only worth what the statement beside it vouches for, and the
    // server reads an id with no statement as no identity at all.
    if (Replica.id && Replica.token) {
      greeting.replica_id = Replica.id;
      greeting.replica_token = Replica.token;
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

      // Whatever was here goes first. Two connects can be in flight at once - a retry scheduled
      // by a dying stream, and a deliberate restart under a new identity - and the second to
      // arrive would otherwise leave the first's stream open with nothing referring to it,
      // delivering every action and every frame a second time.
      $.eventSource?.close();

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
      //
      // Each of the four hands its MEMORY work to receiveFrame and does its own STORING here,
      // which is what separates what a frame means from who received it.
      $.eventSource.addEventListener("sync_deltas", (event) => {
        const frame = JSON.parse(event.data);
        const written = $.receiveFrame("sync_deltas", frame);

        // Behind memory, and only what the STREAM delivered: the rows this frame wrote, and the
        // place they are dated at, in one transaction. Rows a page carried are not written - every
        // visit carries them again - and neither are the rows a confirmed batch promoted, since
        // the server sends its own frame for that change.
        //
        // Not awaited. What is on screen is already correct, and what this buys is only whether it
        // is still there after a reload.
        Durability.persistFrame(LocalDatabase.records(written), frame.cursor);

        $.tell("sync_deltas", frame);
      });

      $.eventSource.addEventListener("sync_reload", (event) => {
        const frame = JSON.parse(event.data);

        $.receiveFrame("sync_reload", frame);

        $.tell("sync_reload", frame);
      });

      $.eventSource.addEventListener("sync_resync", (event) => {
        const frame = JSON.parse(event.data);

        $.receiveFrame("sync_resync", frame);

        // The stored rows go with the place that dated them, for the same reason the memory ones
        // do. What this browser DID - its identity, its counter, its clock - stays: a resync
        // replaces what the SERVER said, and none of those three are the server's to take away.
        Durability.clear();

        $.tell("sync_resync", frame);
      });

      $.eventSource.addEventListener("synced", (event) => {
        const frame = JSON.parse(event.data);

        $.receiveFrame("synced", frame);

        // Written down through the same call a frame's rows go down by, with no rows, because this
        // frame carries none - which also takes the clock down beside it. The same truthiness the
        // memory half tests, for the same reason: a marker naming no place says nothing about
        // where this client stands.
        if (frame.cursor) {
          Durability.persistFrame([], frame.cursor);
        }

        $.tell("synced", frame);
      });

      $.eventSource.onopen = () => {
        GlobalRegistry.set("sseConnected?", true);

        // The one signal that actually means the network is worth trying again. A batch whose
        // send got no answer is still pending, and this is what wakes the queue that stopped
        // behind it.
        Batches.flush();

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

  // What a frame does to MEMORY - shared by the stream that delivered it and by a tab that was
  // handed it by another tab, since a frame means the same thing wherever it arrives from.
  // Answers the rows a deltas frame wrote, and nothing for the other three kinds.
  //
  // What is deliberately NOT here is the storing. Which caller writes the frame down is a question
  // about ROLES rather than about frames: one tab of a browser holds the stream and stores what it
  // delivered, and the rest apply the same frame to their own memory and store nothing.
  static receiveFrame(event, frame) {
    switch (event) {
      case "sync_deltas": {
        const written = Deltas.apply(frame.deltas);

        // What this client's own pending writes are worth against what just arrived: every batch
        // up to the number the frame names has been applied, so its writes on these rows are in
        // the base now and the fold has to stop putting them on top.
        //
        // In the same turn as the ingest, which is what matters - the repaint below is SCHEDULED
        // rather than run, so the fold that draws the screen happens a frame later and sees the
        // base and the marks together whichever order these two lines are in.
        Batches.land(frame.applied_seq, written);

        // Mid-fill the server hands over no place, because a client holding part of a pot could
        // not honour the claim one makes. Keeping the last place it DID name is what lets a
        // client cut off mid-fill come back asking for everything again rather than for the
        // little that changed since.
        if (frame.cursor !== null) {
          $.syncCursor = frame.cursor;
        }

        $.scheduleRender();

        return written;
      }

      // A notice rather than an order, and saying so is the whole of what the client does with
      // it. Restarting the page would throw away what the person was doing to fix a mismatch
      // they did not cause - and it is not where this is going: the server learns to serve a
      // client built against an older model through lens chains, so a bundle behind the server
      // becomes a thing to adapt to rather than to correct. Until then such a client keeps the
      // stream it has, and its database stops filling - no session was started for it, so no
      // completeness marker arrives and everything that waits on one keeps waiting.
      case "sync_reload":
        Logger.debug(`Hologram: bundle behind the server (${frame.reason})`);

        // TODO: nothing reads this yet - an app surfaces it as its own "a new version is
        // available" notice, and a feature helper asserts it the way `sseConnected?` is
        // asserted.
        GlobalRegistry.set("syncStaleReason", frame.reason);

        return null;

      // What follows is the whole of what this client may see rather than what changed in it, so
      // what it holds now is no part of the answer and goes - the place with it, because the place
      // described those rows.
      //
      // Nothing is repainted here on purpose: the refill's own frames schedule that, and the
      // marker ending the refill schedules one even when the refill is empty - which is what
      // takes rows the client may no longer see off the screen in the case that produced them.
      case "sync_resync":
        Logger.debug(`Hologram: sync starting over (${frame.reason})`);
        LocalDatabase.reset();
        $.syncCursor = null;

        return null;

      // The place a client that was filled and then left alone would otherwise never get. A
      // deltas frame carries none until the pot is whole, and once it is whole a quiet app
      // produces no further frame at all - so without this the client would hold everything it
      // was sent and still have nowhere to come back from, and would be filled from nothing on
      // its next visit.
      //
      // Truthy rather than a null test, unlike the deltas kind: a server built before this frame
      // carried a place sends no such key at all, and a rolling deploy can put a new bundle in
      // front of an old node.
      case "synced":
        if (frame.cursor) {
          $.syncCursor = frame.cursor;
        }

        LocalDatabase.markSynced(frame.scope);

        // What a query answers can change the moment a scope is complete - a count that was
        // reading the server's number starts counting rows - so the marker is a reason to
        // render like any frame is.
        $.scheduleRender();

        return null;
    }
  }

  // The frame handed to the other tabs of this browser, which have no stream of their own: only
  // one tab is served sync, and what it receives is every tab's.
  //
  // AFTER the frame has been written down, and that order is the whole of why a tab joining the
  // group cannot miss anything. A write transaction is created before this returns, and IndexedDB
  // orders what follows behind it - so a tab that reads the store on hearing this reads a store
  // that already holds the frame, and a tab that was too late to read it is told by the message.
  //
  // The page the stream was GREETED with rides along, because a completeness marker for a page is
  // a claim about that page rather than about whatever page each tab happens to be on.
  static tell(event, frame) {
    Tabs.post({
      event,
      frame,
      kind: "frame",
      page: GlobalRegistry.get("connectPageModule"),
    });
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

      // Frames keep arriving through a navigation, and between the destination's markup going up
      // and its mount there is a page on screen that the registry cannot yet answer for. A render
      // there would draw the page being LEFT over the destination's virtual document - the same
      // window in which an action is held rather than run. Nothing is lost by standing down: the
      // mount renders when it closes the transition.
      if (Hologram.domEpoch !== Hologram.registryEpoch) {
        return;
      }

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

    $.reconnectTimer = setTimeout(() => $.connect(), delay);
  }
}

const $ = Sse;

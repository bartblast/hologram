"use strict";

import Batches from "./batches.mjs";
import Deltas from "./deltas.mjs";
import Durability from "./durability.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";
import Tabs from "./tabs.mjs";

// The sync half of the realtime stream: what the client greets the server with, the four sync
// kinds the stream delivers, and what a frame does to memory - shared with the tabs that are
// handed a frame by the tab holding the stream.
export default class SyncStream {
  static renderScheduled = false;

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
  // A greeting asking for everything also marks what this client holds as awaiting the fill.
  static buildGreeting(pageModule) {
    const sync = globalThis.Hologram.sync;

    // A tab that does not lead its group says nothing about sync, so the server starts no session
    // for it and sends it no frames. ONE session per browser, however many tabs are open: the tab
    // that leads is served sync and hands what it receives to the rest.
    //
    // The connection itself stays. It carries this tab's own realtime traffic - the actions and
    // receipts the server addresses to this instance - which is per tab by design and not the
    // sync session's to consolidate.
    if (pageModule === null || !Tabs.leader) {
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
    } else {
      // A greeting that asks for sync and names no place asks for EVERYTHING, so what this client
      // holds goes back to awaiting the server's word exactly as it does on a resync - there is no
      // frame in front of this one saying so, and a whole fill follows all the same.
      //
      // The case it exists for is a client cut off part way through a fill: it gave up its place
      // when that fill began and never got a new one, so it comes back here - and the rows the
      // unfinished fill had already delivered are unmarked, which would leave one revoked since
      // standing for the life of the tab.
      //
      // Only here, past the return above: a tab that does not lead and a page that has not mounted
      // greet with nothing, and marking rows for a fill that never arrives would have the leader's
      // own completeness sweep take away rows this browser rightly holds.
      LocalDatabase.beginRefill();
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

  // The four sync kinds carry JSON rather than the JavaScript every other kind on this
  // stream is written in - a delta holds the values a database stores, and spelling those as
  // source costs ten times the bytes on the payload a whole-app fill is mostly made of.
  //
  // Each of the four hands its MEMORY work to receiveFrame and does its own STORING here,
  // which is what separates what a frame means from who received it.
  static listen(eventSource) {
    eventSource.addEventListener("sync_deltas", (event) => {
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

    eventSource.addEventListener("sync_reload", (event) => {
      const frame = JSON.parse(event.data);

      $.receiveFrame("sync_reload", frame);

      $.tell("sync_reload", frame);
    });

    eventSource.addEventListener("sync_resync", (event) => {
      const frame = JSON.parse(event.data);

      $.receiveFrame("sync_resync", frame);

      // The stored rows go with the place that dated them, for the same reason the memory ones
      // do. What this browser DID - its identity, its counter, its clock - stays: a resync
      // replaces what the SERVER said, and none of those three are the server's to take away.
      Durability.clear();

      $.tell("sync_resync", frame);
    });

    eventSource.addEventListener("synced", (event) => {
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
      // every row it holds goes back to awaiting the server's word - and stays on the screen, and
      // stays readable and writable, until the marker ending the refill says which of them the
      // server no longer sends. The place goes now either way, because it described the rows the
      // refill replaces.
      //
      // Somebody else signing in is the exception, and the only one: those rows were another
      // person's and this person may not see them, so they go before anything can read them. Told
      // apart by the reason the server itself spells for it - `durability.mjs` posts the same word
      // for the page-load half of the same event, rather than the sentence it logs.
      //
      // Nothing is repainted here on purpose: the refill's own frames schedule that, and the
      // marker ending the refill schedules one even when the refill is empty - which is what
      // takes rows the client may no longer see off the screen in the case that produced them.
      case "sync_resync":
        Logger.debug(`Hologram: sync starting over (${frame.reason})`);

        if (frame.reason === "identity") {
          LocalDatabase.reset();
        } else {
          LocalDatabase.beginRefill();
        }

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
}

const $ = SyncStream;

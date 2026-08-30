"use strict";

import Batches from "./batches.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";
import Sse from "./sse.mjs";

// The tabs of one replica, and which of them speaks to the server for the rest.
//
// Two tabs of one app are two views onto ONE browser's copy of the data: they share the stored
// rows, the queue of writes waiting to go out, and the identity those writes are numbered under.
// What they must not share is the WORK - two streams download every frame twice, and two senders
// can spend one number on two different batches. So one tab of a group leads: it holds the sync
// stream and sends the queue, and hands what it receives to the others over a channel they all
// listen on.
//
// The election is a Web Lock held for the life of the leader, and it is the browser that runs it
// rather than any bookkeeping of ours. A tab asks for the group's lock; granted, it leads, and it
// keeps the lock by never finishing. Refused, it follows and asks again WITHOUT giving up - which
// is a queue the browser grants in request order, so when the leading tab is closed, crashes or
// goes elsewhere, the browser hands the group to whichever tab has waited longest. No heartbeat,
// no timeout, and nothing ever asks whether the leader is still alive: the browser is the one
// thing that knows, and a granted lock is how it says so.
//
// A GROUP is one model's database and one user. Tabs on different bundles cannot share a database
// - each model version has one of its own - and tabs under different users cannot share a leader,
// because a leader can only send what the session it holds is allowed to send.
//
// A tab in no group LEADS ITSELF, which is what keeps every single-tab case exactly what it was
// before any of this: joining is what makes a tab a follower, and nothing else does.
export default class Tabs {
  static leader = true;

  // The group this tab belongs to, and nothing when it belongs to none.
  static name = null;

  static #channel = null;

  // Frames that arrived before this tab had finished starting up, in the order they arrived.
  static #held = [];

  // The lock request that IS this tab's leadership - answered once the lock has really been let
  // go, which is what makes leaving something a caller can wait for.
  static #holding = null;

  static #onLead = null;

  static #onMessage = null;

  // Whether this tab has taken up what it holds and can be told what the server said.
  static #ready = false;

  static #release = null;

  // Which visit to a group a waiting lock request belongs to. A tab that leaves while waiting is
  // granted the lock eventually anyway, and taking the lead of whatever group it has joined SINCE
  // on the strength of a request it made for one it has left is exactly wrong. Checked when the
  // request fires rather than called off with a signal, because the check also covers the grant
  // that arrives in the same turn as the leaving.
  static #token = null;

  // The group is over, because the thing that made it one is gone: with no store there is nowhere
  // to file a batch and nothing to share, so every tab goes back to being a replica of its own -
  // which is exactly what a tab is in a browser that never had storage at all.
  //
  // The tab that was LEADING keeps the identity and the queue. Those batches were numbered under
  // that identity, it is the only tab that can still send them, and nothing else about it changes.
  //
  // Every other tab takes the fresh identity its own page was minted, lets the batches go, and
  // opens a stream of its own - which it needs, because the frames it was being handed stop here.
  // Answers once the lock is really gone, the way leaving does - which is what lets anything
  // waiting on this tab's place in the group wait for it rather than for a moment.
  static dissolve() {
    const followed = !Tabs.leader;
    const released = Tabs.leave();

    if (followed) {
      Batches.disown();
      Replica.refresh();
      Sse.reconnect();
    }

    return released;
  }

  // Joins the group, answering whether this tab leads it.
  //
  // Awaited at startup, before the mount and before the stream opens, which is what `ifAvailable`
  // buys: it asks whether the lock is free and answers at once either way, rather than waiting for
  // one somebody else holds for as long as their tab is open. So the first tab of a group greets
  // the server with sync on its first connect, and a follower never opens a sync session it would
  // have to drop a moment later.
  static async join(name, {onLead, onMessage}) {
    // A browser that cannot hold a lock, or cannot carry a message between tabs, has no group to
    // join: this tab leads itself and speaks for nobody, which is what every tab there does. Its
    // database is in memory mode for the same reason, so the tabs of such a browser share nothing
    // and there is nothing for this one to coordinate.
    if (
      typeof BroadcastChannel !== "function" ||
      !globalThis.navigator?.locks
    ) {
      Logger.debug(
        "Hologram: this browser cannot coordinate its tabs, this one syncs on its own",
      );

      Tabs.leader = true;

      return true;
    }

    const token = {};

    Tabs.#held = [];
    Tabs.#onLead = onLead;
    Tabs.#ready = false;
    Tabs.#token = token;
    Tabs.name = name;

    Tabs.#onMessage = onMessage ?? Tabs.receive;

    Tabs.#channel = new BroadcastChannel(name);
    Tabs.#channel.onmessage = (event) => Tabs.#deliver(event.data);

    let answer;

    const granted = new Promise((resolve) => {
      answer = resolve;
    });

    // The request's OWN promise is not what is awaited here: for a tab that gets the lock it does
    // not settle until the lock is let go, which is the whole life of the leader. What the grant
    // is worth is known inside the callback, and that is what travels out.
    Tabs.#holding = navigator.locks.request(
      `${name}.leader`,
      {ifAvailable: true},
      (lock) => {
        answer(lock !== null);

        if (lock === null) {
          return;
        }

        return Tabs.#hold();
      },
    );

    Tabs.leader = await granted;

    if (!Tabs.leader) {
      Tabs.#wait(name, token);
    }

    return Tabs.leader;
  }

  // Gives up the group: the lock goes, so the tab that has waited longest takes the lead, and the
  // channel goes with it. Answers once the lock has really been released, which a follower's
  // leaving does not have to wait for - it holds none.
  static leave() {
    const released = Tabs.leader ? (Tabs.#holding ?? Promise.resolve()) : null;

    Tabs.#release?.();
    Tabs.#channel?.close();

    Tabs.#channel = null;
    Tabs.#held = [];
    Tabs.#holding = null;
    Tabs.#onLead = null;
    Tabs.#onMessage = null;
    Tabs.#ready = false;
    Tabs.#release = null;
    Tabs.#token = null;

    Tabs.leader = true;
    Tabs.name = null;

    return released ?? Promise.resolve();
  }

  // What the group's messages mean, and the whole of what one tab does on hearing another.
  //
  // Public so a test can drive it without a channel, and because `join` hands it to the channel as
  // the handler when a caller names none - which is every caller but a test.
  static receive(message) {
    switch (message.kind) {
      // What the tab holding the stream was told, applied here to this tab's own memory. Nothing
      // is stored: the tab that received it wrote it down already, and one store written by two
      // tabs is two tabs racing over one place.
      //
      // A "page" scope is the exception, because it is not the same claim for everyone: it says
      // the page the STREAM was greeted with can be answered from what the client holds, which is
      // this tab's business only if it is on that page.
      case "frame":
        if (Tabs.#foreignPageScope(message)) {
          return;
        }

        Sse.receiveFrame(message.event, message.frame);

        return;

      // A tab that has finished starting up, asking for what the store could not tell it: the
      // scopes, which nothing writes down, and the place and the identity as they stand now.
      // Answered by the tab that has them.
      case "joined":
        if (Tabs.leader) {
          Tabs.postState();
        }

        return;

      case "state":
        Tabs.#takeState(message);

        return;
    }
  }

  // Says something to every OTHER tab of the group: a channel never delivers to the tab that
  // posted, so nothing here needs to know which tab it is. Silent outside a group.
  static post(message) {
    Tabs.#channel?.postMessage(message);
  }

  // This tab has everything it starts with - the rows its own page carried, and what a previous
  // page load left in the browser - so what the server has said since may land on it now. Whatever
  // was held goes through in the order it arrived.
  static ready() {
    const held = Tabs.#held;

    Tabs.#held = [];
    Tabs.#ready = true;

    for (const message of held) {
      Tabs.#onMessage(message);
    }
  }

  // A frame is what the SERVER said, and it lands on top of what this tab already holds: the rows
  // its own page carried, which go in at the mount, and the rows the browser had stored, which go
  // in just after it. A frame arriving before either has nothing to land on - and one declaring a
  // scope complete would be declaring it over rows this tab has not put in yet - so it waits.
  //
  // Nothing else waits. A batch another tab filed, an answer, and the group's state are all about
  // what this BROWSER did rather than what the server said, and none of them has an order to keep
  // against the page's own rows.
  static #deliver(message) {
    if (!Tabs.#ready && message.kind === "frame") {
      Tabs.#held.push(message);

      return;
    }

    Tabs.#onMessage(message);
  }

  // What this tab knows that a tab joining cannot read out of the store: the identity in use, the
  // place the stream has reached, and the scopes the server has declared complete.
  static postState() {
    Tabs.post({
      cursor: Sse.syncCursor,
      kind: "state",
      page: GlobalRegistry.get("connectPageModule"),
      replica: Replica.current(),
      synced: LocalDatabase.syncedScopes(),
    });
  }

  // Whether a completeness marker is about a page this tab is not on. The scope travels with the
  // page the STREAM was greeted with, which is the leader's page rather than everyone's.
  static #foreignPageScope(message) {
    if (message.event !== "synced" || message.frame.scope !== "page") {
      return false;
    }

    const pageModule = Hologram.currentPageModule();

    return (
      pageModule === null ||
      Interpreter.moduleExName(pageModule) !== message.page
    );
  }

  // The promise that IS the lock being held. A lock lasts exactly as long as the function granted
  // it has not finished, so leading is spelled as a promise nothing resolves until this tab lets
  // go - and the browser releases it for us whatever ends the tab, which is the whole reason the
  // succession needs nothing said.
  // The group's state, taken by a tab that has just joined or has just been told the leader
  // changed. The identity is taken outright - one browser presents one - and the place only when
  // this tab holds none, since a place it has is one its own reading has already brought it to.
  static #takeState(message) {
    if (message.replica?.id) {
      Replica.adopt(message.replica);
    }

    if (Sse.syncCursor === null && message.cursor !== null) {
      Sse.syncCursor = message.cursor;
    }

    for (const scope of message.synced) {
      if (
        !Tabs.#foreignPageScope({
          event: "synced",
          frame: {scope},
          page: message.page,
        })
      ) {
        LocalDatabase.markSynced(scope);
      }
    }
  }

  static #hold() {
    return new Promise((resolve) => {
      Tabs.#release = resolve;
    });
  }

  // Asks for the group's lock and does not give up. The browser grants waiting requests in the
  // order they were made, so this IS the succession - it fires when the tab that was leading stops
  // leading, whatever it was in the middle of and whether or not it meant to stop.
  static #wait(name, token) {
    Tabs.#holding = navigator.locks.request(`${name}.leader`, () => {
      if (Tabs.#token !== token) {
        return;
      }

      Tabs.leader = true;
      Tabs.#onLead();

      return Tabs.#hold();
    });
  }
}

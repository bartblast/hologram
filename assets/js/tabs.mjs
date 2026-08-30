"use strict";

import Logger from "./logger.mjs";

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
    Tabs.#onMessage = onMessage;
    Tabs.#ready = false;
    Tabs.#token = token;
    Tabs.name = name;

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

  // The promise that IS the lock being held. A lock lasts exactly as long as the function granted
  // it has not finished, so leading is spelled as a promise nothing resolves until this tab lets
  // go - and the browser releases it for us whatever ends the tab, which is the whole reason the
  // succession needs nothing said.
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

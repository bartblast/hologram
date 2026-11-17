"use strict";

import Batches from "./batches.mjs";
import Durability from "./durability.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";
import Sse from "./sse.mjs";
import SyncStream from "./sync_stream.mjs";

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
// A GROUP is one database and one user. Tabs on different models or sync protocols cannot share a
// database - each pair has one of its own - and tabs under different users cannot share a leader,
// because a leader can only send what the session it holds is allowed to send.
//
// A tab in no group LEADS ITSELF, which is what keeps every single-tab case exactly what it was
// before any of this: joining is what makes a tab a follower, and nothing else does.

// What a tab that has not finished starting up holds rather than acts on, because each of these
// lands ON something the tab has not taken up yet - see `#deliver`.
const HELD_UNTIL_READY = new Set(["answered", "frame", "state"]);

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

  // Whether the group became this tab's to lead while it was still starting up, so it takes the
  // lead once it is ready (see #wait).
  static #leadWhenReady = false;

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
  // A tab still starting up has no stream to replace: the one its page opens after the mount
  // greets the server as the replica of its own it now is, and opening one before the mount would
  // greet it with none of the page's subscriptions (see where the page starts it, in hologram.mjs).
  //
  // Answers once the lock is really gone, the way leaving does - which is what lets anything
  // waiting on this tab's place in the group wait for it rather than for a moment.
  static dissolve() {
    const followed = !Tabs.leader;
    const released = Tabs.leave();

    if (followed) {
      Batches.disown();
      Replica.refresh();

      if (Sse.isStarted) {
        Sse.reconnect();
      }
    }

    return released;
  }

  // Joins the group, answering whether this tab leads it.
  //
  // Awaited at startup, before the store is read, so nothing the group says in between is missed
  // (see DataLayer.boot). And before the mount and before the stream opens, which is what
  // `ifAvailable` buys: it asks whether the lock is free and answers at once either way, rather
  // than waiting for one somebody else holds for as long as their tab is open. So the first tab of
  // a group greets the server with sync on its first connect, and a follower never opens a sync
  // session it would have to drop a moment later.
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
    Tabs.#leadWhenReady = false;
    Tabs.#onLead = onLead ?? Tabs.#lead;
    Tabs.#ready = false;
    Tabs.#token = token;
    Tabs.name = name;

    // Leading nothing until the lock says otherwise: a tab in no group leads itself, but one asking
    // to join speaks for nobody yet. A batch another tab seals during the ask is not this one to
    // send, and a group that dissolves during it takes back what it handed this tab.
    Tabs.leader = false;

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

        // Not held for a visit that has ended: a lock nothing will ever let go of would leave the
        // group with no tab that can lead it.
        if (lock === null || Tabs.#token !== token) {
          return;
        }

        return Tabs.#hold();
      },
    );

    const leads = await granted;

    // Left while asking - the group dissolved under it, a store failure another tab reported - so
    // this tab leads itself, which is what leaving made it.
    if (Tabs.#token !== token) {
      return Tabs.leader;
    }

    Tabs.leader = leads;

    if (Tabs.leader) {
      // For the tab that joins while this one is still asking for the lock: it finds the lock
      // taken, follows, and asks for the state - and nothing answers, because the tab that would
      // was not yet leading when it asked. Saying so unprompted closes that window.
      Tabs.postState();
    } else {
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
    Tabs.#leadWhenReady = false;
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
      // What the server said about a batch, on its way to every tab that is holding one. A tab
      // that holds it promotes or rolls it back; a tab that does not has nothing to do.
      case "answered":
        Batches.settle(message.seq, message.answer);

        return;

      // What the tab holding the stream was told, applied here to this tab's own memory, whichever
      // page this tab is on: what a frame says is about the rows this browser holds. Nothing is
      // stored: the tab that received it wrote it down already, and one store written by two tabs
      // is two tabs racing over one place.
      case "frame":
        SyncStream.receiveFrame(message.event, message.frame);

        return;

      // A tab that has finished starting up, asking for what the store could not tell it: what is
      // complete, which nothing writes down, and the place and the identity as they stand now.
      // Answered by the tab that has them.
      case "joined":
        if (Tabs.leader) {
          Tabs.postState();
        }

        return;

      // A batch another tab has just filed. Taken up here so this tab folds it too - two views of
      // one browser's data disagreeing about a write the same person just made is the thing the
      // group exists to prevent - and, in the tab that sends, sent without waiting to read the
      // store again.
      case "sealed":
        Batches.adopt([message.record]);

        if (Tabs.leader) {
          Batches.flush();
        }

        return;

      case "state":
        Tabs.#takeState(message);

        return;

      // Another tab could not write, and what it wiped it wiped for the whole browser: the rows
      // and the place they were dated at are gone from a store every tab of the group shares. So
      // this tab stops writing too - going on would date rows the store no longer holds - and the
      // group ends, because what made it one was the store.
      case "storage_failed":
        Durability.detach();
        Tabs.dissolve();

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
  // was held goes through in the order it arrived, and then a lead the group handed this tab while
  // it was starting is taken, from the place it now holds.
  //
  // Except where that lead starts from NOWHERE. A tab that leads with no place asks the server for
  // everything (see #lead), and what it held is then the tail of a fill that began before it was
  // listening - the head of that fill was in the store, which its restore refused for having no
  // place (or for belonging to somebody else). Replayed, the tail's marker would give it a place
  // and call the pot complete over the tail's rows alone, and the lead would then write exactly
  // that to the store. So the frames and the group's state go: the fill repeats the rows, and the
  // stream repeats a stop and the rules. Two things stay. The answers to batches are about the
  // queue, which the new fill does not replace. And the identity the group's state names is the one
  // the queue was numbered under - read before the leader had written it, the store can lack it -
  // so it is taken as the state would have given it, and written down, since this tab now sends
  // under it. (A state its leader posted before its own restore names that page's pair instead, and
  // a tab that held no state keeps the pair its restore settled on: see #1680.)
  static ready() {
    const lead = Tabs.#leadWhenReady;
    const fromNowhere = lead && SyncStream.syncCursor === null;

    const held = fromNowhere
      ? Tabs.#held.filter((message) => message.kind === "answered")
      : Tabs.#held;

    if (fromNowhere) {
      Tabs.#adoptGroupIdentity(Tabs.#held);
    }

    Tabs.#held = [];
    Tabs.#leadWhenReady = false;
    Tabs.#ready = true;

    for (const message of held) {
      Tabs.#onMessage(message);
    }

    if (lead) {
      Tabs.#onLead();
    }
  }

  // Acted on as it arrives, or held until this tab has taken up what it starts with - the rows its
  // own page carried, which go in at the mount, and the rows and batches the browser had stored,
  // which go in just after it.
  //
  // THREE KINDS WAIT, each because it lands on something that is not there yet:
  //
  // A FRAME is the server's word about rows the page and the store have not put in yet.
  //
  // The group's STATE carries what is complete, and marking a type or the pot complete is what
  // SWEEPS the rows a page carried but the stream never vouched for. Swept before the mount it sweeps an
  // empty set, and the page's own carried rows - filed a moment later - are never looked at again,
  // so a row the server would no longer send sits there for the life of the tab. (Reachable
  // whenever a tab is between joining and mounting while another posts state: two tabs opened
  // together, a succession, an identity switch. Found by CodeRabbit on PR #1169.)
  //
  // An ANSWER names a batch this tab takes up in the same breath: settling before the batch is
  // there settles nothing, and the batch is then folded for ever - nothing answers it twice.
  //
  // What does not wait: a batch another tab filed (taking one up twice is taking it up once, since
  // the adopt passes over what it already holds), a tab asking for the group's state (which can be
  // answered at any time), and a storage failure, which is the one message a tab should act on
  // before it has finished anything else.
  static #deliver(message) {
    if (!Tabs.#ready && HELD_UNTIL_READY.has(message.kind)) {
      Tabs.#held.push(message);

      return;
    }

    Tabs.#onMessage(message);
  }

  // What this tab knows that a tab joining cannot read out of the store: the identity in use, the
  // place the stream has reached, what the server has declared complete, the rules the stream
  // syncs under, for a tab whose bundle answers by others, and why the server stopped serving the
  // group, if it did.
  //
  // What is complete travels twice: as `completeness`, the types and the whole pot, and as
  // `synced`, the list of scopes a tab of an earlier build iterates. Builds of one model and one
  // protocol share a group, so a tab of an earlier build can be listening, and it throws on
  // anything that is not a list - before marking anything, and before replaying what it held. The
  // list says "all" once the whole pot is complete, which is the one scope both builds share.
  static postState() {
    const completeness = LocalDatabase.syncedState();

    Tabs.post({
      completeness,
      cursor: SyncStream.syncCursor,
      kind: "state",
      replica: Replica.current(),
      rules: SyncStream.rulesForGroup(),
      stopReason: SyncStream.stopReason,
      synced: completeness.all ? ["all"] : [],
    });
  }

  // What a tab does the moment the group becomes its to lead, which is the moment the tab that was
  // leading closed, crashed or went elsewhere - with nothing handed over, because there may have
  // been nobody left to hand anything over.
  //
  // Everything it needs is in its own memory, in the store, or in the grant itself.
  //
  // Read before anything is awaited: whether this tab's page has opened its stream yet. A tab
  // handed the lead while starting takes it from ready(), before its page starts the stream, and
  // that stream greets the server as the leader all by itself.
  static async #lead() {
    const started = Sse.isStarted;

    if (SyncStream.syncCursor === null) {
      // Nowhere to be brought up to date FROM: the tab that was leading died mid-fill, or never
      // got far enough to have a place. So this one asks for everything again, and says so to the
      // group, whose tabs hold the same rows out of the same store.
      //
      // The rows stay on every screen in the meantime, each tab's included: the fill that follows
      // confirms the ones this browser may still see and the marker ending it takes away the rest,
      // which is the same answer arriving without a gap in the middle of it.
      LocalDatabase.beginRefill();
      Durability.clear();

      Tabs.post({
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    } else {
      // The store can be BEHIND what this tab holds: a frame is written down without waiting, so
      // the tab that was leading can have posted one and closed before its write landed. Carrying
      // on from the next frame would leave the store naming a place it does not hold the rows for.
      await Durability.repair(
        LocalDatabase.records(LocalDatabase.vouchedRowKeys()),
        SyncStream.syncCursor,
      );
    }

    Tabs.postState();

    // The stream this tab has is a realtime one - it greeted the server with no sync, being a
    // follower at the time - so it is replaced by one the server serves sync on. A tab handed the
    // lead while starting has none yet: its page starts one right after, which greets as the leader
    // by itself, and a reconnect here would open a second one beside it.
    if (started) {
      Sse.reconnect();
    }

    // And the queue is this tab's to drain now.
    Batches.flush();
  }

  // The identity the last of the given messages that is the group's state names, taken up and
  // written down - for a tab about to send under it (see ready()).
  static #adoptGroupIdentity(messages) {
    const state = messages.findLast((message) => message.kind === "state");

    if (state?.replica?.id) {
      Replica.adopt(state.replica);
      Durability.persistReplica(Replica.current());
    }
  }

  // The group's state, taken by a tab that has just joined or has just been told the leader
  // changed. The identity is taken outright - one browser presents one - and the place only when
  // this tab holds none, since a place it has is one its own reading has already brought it to. A
  // stop is taken whenever the group names one.
  static #takeState(message) {
    if (message.replica?.id) {
      Replica.adopt(message.replica);
    }

    if (SyncStream.syncCursor === null && message.cursor !== null) {
      SyncStream.syncCursor = message.cursor;
    }

    // The rows the group holds were judged under the rules the stream was handed, so a tab whose
    // bundle answers by others takes those - a page served by a node still on the old build, say.
    if (
      message.rules &&
      message.rules.policy_hash !== globalThis.Hologram.sync?.policyHash
    ) {
      SyncStream.receiveFrame("sync_rules", message.rules);
    }

    // For a tab joining a group the server stopped before it was listening. One group is one model
    // and one protocol (see Durability.databaseName), so what stopped the tab that answered stops
    // this one.
    if (message.stopReason) {
      SyncStream.receiveFrame("sync_reload", {reason: message.stopReason});
    }

    // A type's completeness is a claim about the rows this browser holds, the same in every tab
    // and on every page. A tab of an earlier build tells it only as a list of scopes, whose "all"
    // says the same and whose "page" names no type.
    const synced = message.completeness ?? {
      all: message.synced.includes("all"),
      types: [],
    };

    LocalDatabase.markTypesSynced(synced.types);

    if (synced.all) {
      LocalDatabase.markAllSynced();
    }
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
  //
  // A tab still starting up leads from the grant - so its restore judges what it read as the tab
  // that speaks to the store does, refusing rows with no place and writing the identity - but TAKES
  // the lead only once it is ready (see ready()).
  //
  // What the restore judges is the store as the tab READ it, which can be older than what the tab
  // that led wrote since. A fill that finished after the read is refused and filled again, which
  // costs a download. A read taken before that tab recorded who the store belongs to is refused
  // as somebody else's, so the ready tabs drop their rows until the refill. And an identity it
  // wrote since is written over, which ready() puts back when the group's state said it (#1680).
  //
  // Until it is ready it holds no place: the restore is what hands it the one the store had.
  // Taking the lead without one is asking for everything again, clearing the store and telling
  // every tab to drop its marks, and the restore that followed would then greet the server with the
  // place it read, so the fill those tabs wait for would never come and the store would claim rows
  // it no longer holds.
  static #wait(name, token) {
    Tabs.#holding = navigator.locks.request(`${name}.leader`, () => {
      if (Tabs.#token !== token) {
        return;
      }

      Tabs.leader = true;

      if (Tabs.#ready) {
        Tabs.#onLead();
      } else {
        Tabs.#leadWhenReady = true;
      }

      return Tabs.#hold();
    });
  }
}

"use strict";

import Batch from "./batch.mjs";
import Clock from "./clock.mjs";
import Deserializer from "./deserializer.mjs";
import Durability from "./durability.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";
import Mutations from "./mutations.mjs";
import Overlay from "./overlay.mjs";
import Replica from "./replica.mjs";
import Sse from "./sse.mjs";
import SyncStream from "./sync_stream.mjs";
import Tabs from "./tabs.mjs";
import Type from "./type.mjs";

// Which batch an action's writes go to, and what becomes of it when the action ends.
//
// An action opens one on the way in and closes it on the way out, so "the writes of one action"
// needs no bookkeeping from the app: a write goes to the batch of the action making it. A batch
// that collected nothing is dropped rather than sent, and one that collected something is sealed,
// takes the next sequence number and joins the queue in the order it was made.
//
// That order is the order it ships, and the ordering is load-bearing rather than tidy: a later
// batch may name a row an earlier one created, and its based_on for a column an earlier one wrote
// is that batch's own stamp. Shipping them out of order turns a sound chain into a refusal.
//
// ONE SLOT rather than a stack of open batches, because "the batch opened last" is not "the batch
// of the action running now": an action that awaits is still open while another runs, so a stack
// would hand the resuming action whichever batch started while it was away - its writes would join
// that one, and its close would seal it. The slot is emptied where an action stops running and put
// back when it resumes, which is the whole of carryAcrossSuspension - so a write, a close and a
// discard all reach the batch of the action that asked for them, whatever else began meanwhile.
export default class Batches {
  // Sealed and waiting to ship, oldest first.
  static pending = [];

  // Refused by the server, holding what it said. The queue surface an app can list, and the
  // devtools inspector, are the readers.
  //
  // TODO: filled when the sender loop records a refusal.
  static rejected = [];

  // The numbers of the batches this tab has heard answered, whether or not it held them: an answer
  // can reach a tab before the message announcing the batch does. Kept for the life of the page,
  // because that message can arrive after the store has let go of the batch, so the store can't
  // say the batch was ever there.
  static #answered = new Set();

  // The batch of the action running right now, and nothing when no action is - a write outside an
  // action has nowhere to belong.
  // The tries a batch nobody answered has had so far, which is what the next delay is computed
  // from. Back to nothing the moment any batch is answered - a server that is answering again
  // has earned the short delay, whatever it cost to reach it.
  static #retryAttempts = 0;

  // The retry waiting to fire, and nothing while none is. Not cleared by the other wake-ups, and
  // deliberately: a run of the loop ends with the queue empty, with a retry it has just
  // rescheduled itself, or - in a tab the server stopped - with its batches held, so a timer left
  // standing by an earlier run never finds work - it is the guard, the empty queue and the hold
  // that make it harmless, and a clear on every entry would be a line nothing could ever observe.
  static #retryTimer = null;

  // The batch whose refused switch the retry was set for, which waits out that retry and no other
  // (see flush).
  static #retryFor = null;

  static #running = null;

  // Batches of another user still on their way into the store. They have left the queue, and a page
  // about to be loaded afresh has to wait for them all the same (see recorded).
  static #filing = new Set();

  // Batches of actions still open that a change of user took off the screen. Nothing else holds
  // them for the overlay, so this is what puts them back if their user returns before they close.
  static #releasedOpen = new Set();

  // Sealed batches of other users that no store holds, by user: the ones this tab made where there
  // was nowhere to file them. A change of user takes them off the queue, and nothing else holds
  // them, so this is what sends them once their user is signed in again.
  static #setAside = new Map();

  // Batches of other users whose filing was still out at the change of user, by user. Where the
  // filing finds no store they're set aside like the ones above. A user signed in again before that
  // takes theirs back at once, rather than after the actions started since.
  static #filingAside = new Map();

  // The order the batches of both maps above were made in, which is the order they come back in:
  // one still filing can be older than one set aside, and neither has a number to sort by yet. A
  // batch keeps its place until it comes back, however many times it moves between the maps.
  static #asideOrder = new Map();
  static #asideCount = 0;

  // One batch is in flight at a time, and the loop that keeps it that way must not be entered
  // twice - every close calls flush, and an answer can arrive while another action is running. Held
  // while it runs, for a caller that has to know when it has finished.
  static #drain = null;

  // Batches let go of while their filing was still in flight (see disown).
  static #disowned = new WeakSet();

  static #seq = 0;

  // An action that awaits stops running, and another action may run to completion before it comes
  // back - so the batch it opened is taken out of the slot here and put back in the turn it
  // resumes, before any of its remaining code runs. Task.await/1 is the only place an action stops:
  // every JS promise reaching Elixir is boxed as a Task, and nothing else unwraps one.
  // Batches this tab did not make, taken up as its own: the ones a previous page load left behind,
  // and the ones another tab of this browser has filed since. Into the queue, so they ship, and
  // into the overlay, so their rows are on the screen before anything is sent - which is what makes
  // two tabs of one browser show the same thing.
  //
  // In the order they were made, which is the order they must go out in: a later batch may name a
  // row an earlier one created.
  //
  // Passed over three ways. A batch this tab already holds - its own, or one adopted twice - would
  // otherwise be folded and sent twice. A batch already answered would be too, and its writes
  // promoted over a base that has them: the message announcing a batch can arrive after its answer.
  // A batch of ANOTHER user is left where it is, since the server applies a batch under the user of
  // the session that sends it, and the page mounted under its owner is what will take it up. And in
  // every case the counter still follows it: `#seq` is what this tab has SEEN, so a number spent by
  // another tab is a number this one will not spend.
  //
  // The CLOCK follows the writes it takes, for the same reason it follows a frame's revisions: a
  // batch this tab seals next may name a row one of these wrote, and its `based_on` for that column
  // is that batch's stamp - a stamp of this tab's own that did not clear it would be refused.
  //
  // Deliberately does NOT send. Waking the sender belongs to whatever took these up, once
  // everything it takes up is in place - and a function that only picks things up is one a test can
  // call without reaching the network.
  static adopt(records) {
    const owner = LocalDatabase.actorUserId ?? null;

    let taken = false;

    for (const record of records) {
      Batches.#seq = Math.max(Batches.#seq, record.seq);

      const held = Batches.pending.some((batch) => batch.seq === record.seq);

      if (
        held ||
        record.actorUserId !== owner ||
        Batches.#answered.has(record.seq) ||
        Durability.wasAnswered(record.seq)
      ) {
        continue;
      }

      const batch = Batch.fromRecord(record);

      for (const write of batch.writes) {
        if (write.stamp) {
          Clock.observe(write.stamp);
        }
      }

      Batches.pending.push(batch);
      Overlay.insert(batch);

      taken = true;
    }

    if (taken) {
      Batches.#sort();
      SyncStream.scheduleRender();
    }
  }

  static carryAcrossSuspension(promise) {
    const batch = Batches.#running;

    // Registered before the slot is emptied, so nothing that is not really a promise empties it -
    // the action stays running and its raise still reaches its own writes. The callback cannot run
    // before this returns, since a settled promise still calls back in a later turn.
    const carried = promise.finally(() => {
      Batches.#running = batch;
    });

    Batches.#running = null;

    return carried;
  }

  // Seals the batch the action opened, or drops it when the action wrote nothing - a sequence
  // number is spent only by a batch that will ship. Answers the sealed batch, or nothing when
  // there was nothing to seal.
  static close() {
    const batch = Batches.#running;

    if (batch === null) {
      return null;
    }

    Batches.#running = null;
    Batches.#releasedOpen.delete(batch);

    if (batch.writes.length === 0) {
      Overlay.remove(batch);

      return null;
    }

    batch.mark("pending");

    // The user changed while the action was suspended, so this tab can't send the batch: the server
    // applies a batch under the user of the session that sends it. It waits in the store for a page
    // of its owner. Where there is no store, it waits in this tab (see releaseForeign).
    if (batch.actorUserId !== (LocalDatabase.actorUserId ?? null)) {
      Overlay.remove(batch);

      batch.recorded = Batches.#number(batch);
      Batches.#trackFiling(batch);
      Batches.#putAside([batch]);

      return batch;
    }

    Batches.pending.push(batch);

    // Started here and awaited by the sender, so the batch is on its way down while the action's
    // own render happens - the store is never on the path of what the user sees.
    //
    // The NUMBER comes with the filing rather than before it, which is the whole of what makes a
    // browser's tabs safe to share a queue: a counter each tab moved in its own memory is a number
    // two tabs can spend at once, and the second batch filed under it overwrites the first. So the
    // batch joins the queue unnumbered and takes its place in the order once it has one.
    batch.recorded = Batches.#number(batch);

    return batch;
  }

  static current() {
    return Batches.#running;
  }

  // Settles once every batch this tab has sealed is written down - for a page about to be loaded
  // afresh, which would otherwise leave behind a batch whose write had not finished. Asked again
  // after each wait, since the page is live through it and an action can seal another. Never
  // rejects: a write that failed has said so already, and the load goes ahead either way.
  //
  // What an action suspended across an await has written is not waited for: its batch is sealed
  // only when the action comes back, which is app code, and may never be.
  static async recorded() {
    const waited = new Set();

    while (true) {
      const sealed = [...Batches.pending, ...Batches.#filing].filter(
        (batch) => !waited.has(batch),
      );

      if (sealed.length === 0) {
        return;
      }

      for (const batch of sealed) {
        waited.add(batch);
      }

      await Promise.allSettled(sealed.map((batch) => batch.recorded));
    }
  }

  // Every batch the store holds, let go: out of the queue, so this tab does not send it, and out
  // of the overlay, so nothing is shown that this tab can no longer learn the fate of.
  //
  // For a tab whose group has DISSOLVED. Those batches were numbered under the group's identity,
  // the tab that kept that identity is still sending them, and this one - which is moving to an
  // identity of its own - would be sending a second copy of each under a number nothing has
  // recorded against it. The server would apply them twice.
  //
  // The rows go back to what the server last said, and come back when its answer to those batches
  // does, through this tab's own stream, as an ordinary frame. That gap is what a store breaking
  // mid-session costs a tab that was not the one sending.
  //
  // A batch the store doesn't hold stays: it exists nowhere else, so no other tab will send it. One
  // whose filing is still in flight can go either way, so it's decided when the filing settles.
  static disown() {
    Batches.pending = Batches.pending.filter((batch) => {
      if (batch.filed === null) {
        Batches.#disowned.add(batch);
      } else if (batch.filed) {
        Overlay.remove(batch);
      }

      return !batch.filed;
    });
  }

  // Lets go of every batch of a user other than the given one: out of the queue, so this tab does
  // not send it under the new user's session, and out of the overlay, so the new user doesn't see
  // it. An action still open counts, since its batch is in the overlay from the moment it opens.
  // The given user's that an earlier change took off the queue or the screen come back.
  //
  // Unlike disown, nothing else holds these for this tab. They stay in the store, which is where
  // their owner's next page takes them up. The ones no store holds stay in this tab, which sends
  // them once their owner is signed in again. Until then they're the reason to keep the owner's
  // pair (see heldFor).
  static releaseForeign(owner) {
    // A mount can leave the actor undefined, and batches of a visitor are stamped null.
    const current = owner ?? null;
    const isForeign = (batch) => batch.actorUserId !== current;
    const foreign = Batches.pending.filter(isForeign);

    foreign.forEach(Batches.#trackFiling);
    Batches.#putAside(foreign);
    Batches.pending = Batches.pending.filter((batch) => !isForeign(batch));

    for (const batch of Overlay.removeWhere(isForeign)) {
      if (batch.state === "open") {
        Batches.#releasedOpen.add(batch);
      }
    }

    // Ahead of the open ones, which were made after them, in the order they were made. One answered
    // while it waited is done.
    const away = [
      ...(Batches.#setAside.get(current) ?? []),
      ...(Batches.#filingAside.get(current) ?? []),
    ].sort(
      (left, right) =>
        Batches.#asideOrder.get(left) - Batches.#asideOrder.get(right),
    );

    Batches.#setAside.delete(current);
    Batches.#filingAside.delete(current);
    away.forEach((batch) => Batches.#asideOrder.delete(batch));

    const returning = away.filter(
      (batch) => batch.seq === null || !Batches.#answered.has(batch.seq),
    );

    for (const batch of returning) {
      Batches.pending.push(batch);

      if (batch.seq === null) {
        Overlay.push(batch);
      } else {
        Overlay.insert(batch);
      }
    }

    Batches.#sort();

    for (const batch of Batches.#releasedOpen) {
      if (!isForeign(batch)) {
        Batches.#releasedOpen.delete(batch);
        Overlay.push(batch);
      }
    }
  }

  // Whether this tab holds batches of the given user that no store holds, set aside at a change of
  // user until that user is signed in again.
  static heldFor(owner) {
    return Batches.#setAside.has(owner ?? null);
  }

  // The landed marks the store records, taken into the batches this tab holds - for a tab taking
  // up rows from the store that a stored frame already wrote a batch's writes into (see
  // Tabs.#takeStore). Only added, never taken away: a mark this tab set itself is as true as one
  // the store holds. Nothing is written: the store holds these marks already.
  static takeLanded(records) {
    for (const {landed, seq} of records) {
      const batch = Batches.pending.find((held) => held.seq === seq);

      if (batch !== undefined) {
        for (const index of landed) {
          batch.landed.add(index);
        }
      }
    }
  }

  // Everything the action wrote goes away, which is what a raise has to mean: an action's writes
  // land together or not at all, and dropping the layer is the whole of putting them back.
  static discard() {
    const batch = Batches.#running;

    if (batch !== null) {
      Batches.#running = null;
      Batches.#releasedOpen.delete(batch);

      Overlay.remove(batch);
    }

    return batch;
  }

  // Sends the pending batches, oldest first, ONE AT A TIME. The ordering is not politeness: a
  // later batch may name a row an earlier one created, and its based_on for a column an earlier
  // one wrote is that batch's own stamp - so overlapping them turns a sound chain into a refusal.
  static flush() {
    // ONE TAB OF A BROWSER SENDS, and it is the one holding the group's lock. A batch made in any
    // tab is filed in the one queue they share, so the leader's own reading of that queue is what
    // ships - and a follower that sent as well would put a second copy of every batch on the wire,
    // under the same replica and number, for the server to answer twice from one record.
    //
    // And only once it is ready (see Tabs.sends): a tab that leads while still starting up has not
    // taken up the identity, the counter and the batches the store held, so it would send the
    // stored queue under its page's own identity rather than the one the batches were numbered
    // under. The restore wakes the sender once it has, and so does the lead it takes.
    if (!Tabs.sends()) {
      return Promise.resolve();
    }

    Batches.#drain ??= Batches.#sendPending();

    return Batches.#drain;
  }

  static async #sendPending() {
    try {
      while (true) {
        // The queue as the STORE holds it, before every send rather than once: any tab can file a
        // batch, and the message saying so can arrive late, be missed by a tab that was starting
        // up or never be sent by a tab that closed straight after filing. So what ships is the
        // order the batches were made in, whatever order this tab heard about them.
        //
        // The read starts once the head is filed, and that is what makes it enough. The store hands
        // out numbers inside transactions it runs one at a time, so by the time a batch is filed
        // every lower number is too, and this read sees them all. Started earlier, it could miss a
        // batch another tab filed just ahead of the head. Only below the head, since nothing above
        // it can go first: a batch above is found once the queue has drained down to it.
        //
        // Also what keeps a batch from going out under a number this browser could hand out again
        // after a reload: it is written down before it leaves.
        const head = Batches.pending[0];

        await head?.recorded;

        Batches.#takeUp(await Durability.queuedBatches(head?.seq ?? null));

        const batch = Batches.pending[0];

        // The read found a lower batch, this one joined the queue while it ran, or the head left
        // it. Either way the read says nothing about what goes next, so another one does: with no
        // head it reads the whole queue, which is what finds a batch above the one that left.
        if (batch !== head) {
          continue;
        }

        if (batch === undefined) {
          return;
        }

        // Nothing leaves under an identity still on its way to the store (see
        // Durability.replicaWritten).
        await Durability.replicaWritten();

        // Either wait is long enough for the batch to be let go of (see disown) or answered through
        // another tab, and then it isn't this tab's to send.
        if (!Batches.pending.includes(batch)) {
          continue;
        }

        // No number means no store took this batch, and the tab has no identity of its own to
        // number it under (see #numbered). Every batch the store does hold goes first, including
        // one whose filing may still land. Then the tab asks for an identity and numbers what's
        // left under it, in the order it was made.
        if (batch.seq === null) {
          const filing = Batches.pending.filter((held) => held.filed === null);

          if (filing.length > 0) {
            await Promise.allSettled(filing.map((held) => held.recorded));

            continue;
          }

          if (Batches.pending[0] !== batch) {
            continue;
          }

          if (!Replica.minted && !Replica.withoutIdentity()) {
            Replica.requestMint();

            if (Sse.isStarted) {
              Sse.reconnect();
            }

            return;
          }

          if (Replica.minted) {
            for (const held of Batches.pending) {
              if (held.seq === null) {
                Batches.#numbered(held);
              }
            }
          }
        }

        // A stored batch only ever goes out under the stored identity: under any other, the server
        // has no record of it and would apply it a second time if it has already seen it. It stays
        // in the store for the next page load, which takes up both.
        if (
          batch.filed &&
          Durability.mode === "memory" &&
          !Durability.holdsIdentity()
        ) {
          Batches.#letFiledGo();

          continue;
        }

        // Nothing goes out until the pair this tab asked for arrives (see Replica.requestMint). The
        // handshake that brings it wakes the sender again. One that refused it leaves the writes
        // here until a reload (see Replica.refuseMint).
        if (Replica.withoutIdentity()) {
          return;
        }

        // A tab the server stopped over its model holds its writes rather than sending them to be
        // refused: the server would roll back what the person did over a mismatch they did not
        // cause. They stay in the queue, on the screen and in the store, until a reload takes the
        // page to the new model - the store they are in is the old model's, which is where a
        // reload leaves them.
        //
        // Asked here, after the store has been read and right before the send, rather than once on
        // the way in: the queue is still taken up, so a batch another tab filed is on this tab's
        // screen too, and a stop that arrives while a send is out stops the drain behind it.
        //
        // A hold that ends during that read is asked about once more: the flush its end starts
        // finds this sender busy, so nothing else sends the queue.
        if (SyncStream.holdsWrites()) {
          await Batches.#takeUpWhileHeld();

          if (SyncStream.holdsWrites()) {
            return;
          }

          continue;
        }

        // Asked again here for the same reason: a tab that follows a change of user moves to the
        // new user's group, where it may not be the one that sends. Its send already out finishes,
        // and the queue behind it goes to whichever tab leads there, under that tab's identity.
        if (!Tabs.sends()) {
          return;
        }

        // The user can have changed during the waits above, and the send goes out under the session
        // of whoever is signed in now. A batch with a lower number can have arrived from another
        // tab too, and has to go first. Nothing is awaited from here to the request.
        const owner = LocalDatabase.actorUserId ?? null;

        if (batch.actorUserId !== owner || Batches.pending[0] !== batch) {
          Batches.releaseForeign(owner);

          continue;
        }

        // Told to every tab here, by the tab sending it, whoever filed it. The filing tab's own
        // message can be late or never come, and a tab hearing a frame or an answer about a batch
        // it doesn't hold can't tell what it already has: it would apply the write again over rows
        // that hold it. Frames and answers reach the other tabs from this tab too, after this, and
        // one tab's messages arrive in order.
        //
        // Not one an open store never got, whose answer is withheld too (see below): a tab that
        // took it up would hold a number the store never recorded, and keep it on screen.
        if (batch.filed !== false || Durability.mode === "memory") {
          Tabs.postNow({kind: "sealed", record: batch.record()});
        }

        batch.mark("sending");

        const sentUnder = Durability.sentUnder();
        const answer = await Batches.#answerFor(batch);

        // No verdict about the writes, so the batch stays exactly where it is and the queue stops
        // behind it - a later batch may name a row this one created.
        //
        // Kept rather than discarded, because a failed send does NOT mean the batch did not land:
        // a response can be lost after the server committed, and a resend of the same
        // (replica_id, seq) is answered from the record rather than applied twice.
        //
        // Three things wake it: the next action's close, the connection coming back, and - since
        // neither of those is coming when the stream stays up while the endpoint fails - a retry
        // on the stream's own backoff, scheduled below.
        if (answer.status === "failed") {
          // Let go of while it was out, so it waits in the store for its owner. Its failure says
          // nothing about the pair or the server this tab goes on with.
          if (!Batches.pending.includes(batch)) {
            batch.mark("pending");

            continue;
          }

          // Refused with no store to record a new identity in, a stored batch can't move to one:
          // if an earlier send landed, the server would apply it again. It waits in the store for
          // the next page load.
          if (
            answer.httpStatus === 403 &&
            batch.filed &&
            Durability.mode === "memory"
          ) {
            batch.mark("pending");
            Batches.#letFiledGo();

            continue;
          }

          // A 403 says the IDENTITY was refused, before the writes were read - a stored statement
          // stops verifying when the session it was bound to is gone, and after the server's
          // signing key is rotated every stored one does. Presenting it again would be refused
          // again forever, and the recovery is a pair this page is already holding: the fresh one
          // the server minted for this render.
          //
          // The stream is restarted so the server serves the NEW replica - the one this stream was
          // opened for is the refused one, and its frames would name no watermark, which is what
          // stops this client applying its own writes twice. The batch keeps its number: nothing
          // has been recorded against the new identity, so any number is free under it.
          //
          // Once per backoff: a batch refused again under the pair it switched to waits for the
          // retry timer, which lets it switch again (see #scheduleRetry). Every handshake hands the
          // tab a new pair (see DataLayer.takeHandshake), so a refusal that no pair cures, a failed
          // CSRF check after the session was reset, would otherwise switch, reconnect and resend
          // for as long as it lasts - the new stream's flush included. `refresh` answers false
          // when the fresh pair is already the one in use, which nothing here can help.
          //
          // AWAITED, the same discipline the counter's write gets and for the same reason: nothing
          // is sent under an identity that is not recorded. Fired and forgotten, a reload landing
          // before the write commits would take up the REFUSED pair again while the counter had
          // moved on - and the batch that followed would be refused a second time before this path
          // could recover it.
          if (
            answer.httpStatus === 403 &&
            !batch.switchedPair &&
            Replica.refresh()
          ) {
            batch.switchedPair = true;

            await Durability.persistReplica(Replica.current());

            // The other tabs of this browser present the refused pair too, and would each find
            // that out the hard way. One switch, told once.
            Tabs.postState();

            Sse.reconnect();

            continue;
          }

          batch.mark("pending");

          console.warn(
            `Hologram: batch ${batch.seq} was not answered (${answer.httpStatus}) - it stays pending and goes again shortly, on the next write, or on reconnect`,
          );

          // Before the retry is set: one firing during this read would find the sender busy and
          // be lost. A batch waiting out a switch waits for the retry set for it, and not for one
          // an earlier batch left, which ends sooner. Pushed back by every flush the user's actions
          // start, it would never get to switch to the pair the next handshake hands.
          await Batches.#takeUpWhileHeld();

          if (!batch.switchedPair || Batches.#retryFor !== batch) {
            Batches.#scheduleRetry(batch.switchedPair ? batch : null);
          }

          return;
        }

        // A refusal that judges the BUILD rather than the writes is no verdict about them. The
        // server refused the batch because this bundle was built against another model, which is
        // what a stop over the model says - and a send can reach the server before the stream
        // does, since opening the stream is what wakes the queue. So it is taken as that stop: the
        // batch goes back to waiting, nothing is forgotten, settled or told to the group as
        // answered, and the drain stops, with no retry - a reload is what moves it on. The server
        // records nothing for such a refusal, so a later send of the same batch is judged afresh.
        //
        // Kept while the tab lives, and no longer than that: after a reload the new bundle opens
        // another model's store, and the batch stays in the old one.
        if (Batches.#refusesBuild(answer)) {
          batch.mark("pending");

          const frame = {reason: "model_hash"};

          SyncStream.receiveFrame("sync_reload", frame);
          SyncStream.tell("sync_reload", frame);

          await Batches.#takeUpWhileHeld();

          return;
        }

        // A verdict is a verdict, whichever way it went: nothing is waiting on this batch any
        // more, and a later page load has no reason to take it up. Confirmed and refused alike -
        // including the refusal that judges the STAMPS rather than the writes (`:clock`), which the
        // server does not record and would evaluate afresh on a resend. Keeping one for that resend
        // was weighed and refused (D5): the rows are off the screen already, so a batch kept would
        // come back days later as a write the user watched fail, and a device whose clock is
        // permanently wrong would resend it on every page load with nothing in v1 able to discard
        // it.
        //
        // Every tab of the group holds this batch and every one of them has to let it go - the
        // answer reaches them as it arrived, undecoded, because a client term is not something a
        // browser can carry from one tab to another. Told first: a delete that fails on the spot
        // ends the group, and a tab that never heard would send the batch again.
        //
        // Not for a batch an open store never got, though: no tab heard of it, and its number was
        // never recorded, so what the store holds under it can be another tab's batch. A tab with
        // no store files nothing, and its forget checks whose the number is (see forgetBatch).
        if (batch.filed !== false || Durability.mode === "memory") {
          Tabs.post({answer, kind: "answered", seq: batch.seq});

          Durability.forgetBatch(batch.seq, sentUnder);
        }

        Batches.settle(batch.seq, answer);
      }
    } finally {
      Batches.#drain = null;
    }
  }

  // Marks, on every batch the server has already applied, the writes naming the rows a frame just
  // wrote. Those writes are in the base now, as the server resolved them, so the fold has to stop
  // putting them on top - and for a moved counter that is the difference between showing the
  // number the server holds and showing one more than it.
  //
  // Up to the number and no further. A batch above it has not been applied, so its writes are
  // still this client's own to show. A batch still IN FLIGHT counts: it sits in the queue until
  // its answer arrives, and its effects can reach the stream before that answer does, which is
  // the whole case this exists for. The open batch is not in the queue at all and cannot be
  // landed - nothing of it has been sent.
  //
  // A frame naming no number says NOTHING about this client's writes, which is not the same as
  // saying none of them have landed - so nothing is marked.
  //
  // WHAT MAKES THIS SAFE IS THE SENDER, NOT THE NUMBER. The number is a MAXIMUM over the batches
  // the server confirmed, and the set can be sparse: a batch can be refused with a later one
  // confirmed above it. Taking every batch at or below a maximum would then be wrong, were it not
  // for how the queue drains - flush() keeps ONE batch in flight and takes the head off `pending`
  // BEFORE it reads the answer, so a refused batch leaves with the answer that refused it. (A batch
  // refused for the bundle rather than for its writes stays, but it was never applied, and nothing
  // is sent after it once the tab holds its writes.) While
  // batch N is pending, nothing above N has been sent, so nothing above N can be confirmed, so a
  // number at or above N can only mean N ITSELF was confirmed - which is exactly when its effects
  // are in the base and landing it is right, answer lost or not.
  //
  // Anything that changes how the queue drains has to keep that property or replace this test. A
  // durable queue, or one leader draining several tabs, is where it would go: batches of one
  // replica answered out of order would make a maximum admit a batch nobody applied.
  static land(appliedSeq, rowKeys) {
    if (!Number.isInteger(appliedSeq)) {
      return;
    }

    for (const batch of Batches.pending) {
      // Written down only where a mark actually moved. Most frames name rows no pending batch has
      // anything to say about, and a batch whose marks are unchanged is already stored the way it
      // stands - so `land` answering false is what keeps the ordinary frame off the disk entirely.
      // A batch still waiting for its number has not been sent, so nothing the server says can be
      // about it - and `null <= appliedSeq` is true, which is why this is spelled out.
      if (
        batch.seq !== null &&
        batch.seq <= appliedSeq &&
        batch.land(rowKeys)
      ) {
        Durability.persistLanded(batch);
      }
    }
  }

  // What a type's fill marker says about the rows this client's own batches created. A batch at or
  // below the marker's number was in what the fill read of the type, so a row of it the fill did
  // not send is gone, or one its user may not read. No frame can be counted on to say so: a session
  // passes over a batch that committed wholly before its fill place, and a batch dispatched before
  // the session joined never reaches it. So the create is landed, and its answer files nothing, in
  // this page load or, since the marks are stored with the batch, in the one that sends it again.
  //
  // Asked after the marker's sweep has run, so a copy of the row the page carried does not pass for
  // one the fill delivered. Only of the marker's own types: each type is read at its own moment,
  // and another type's number says nothing about this one.
  //
  // A batch above the number committed after the read, so its session judges it, and a marker
  // naming no number makes no claim. Like `land`, this relies on the queue going out in number
  // order (see its note on the sender).
  //
  // Every write of these batches naming such a row goes with it, and so does an edge pointing at
  // one, which the fold would otherwise go on showing in a held row's set until the batch's answer.
  static landUnsent(types, appliedSeq) {
    if (!Number.isInteger(appliedSeq)) {
      return;
    }

    // A batch still waiting for its number has not been sent - `null <= appliedSeq` is true.
    const read = Batches.pending.filter(
      (batch) => batch.seq !== null && batch.seq <= appliedSeq,
    );

    const unsent = Batches.#unsentCreates(read, new Set(types));

    if (unsent.size === 0) {
      return;
    }

    for (const batch of read) {
      const marked = batch.landed.size;

      batch.writes.forEach((write, index) => {
        if (
          unsent.has(`${write.type} ${write.id}`) ||
          Batches.#pointsAtAny(write, unsent)
        ) {
          batch.landed.add(index);
        }
      });

      if (batch.landed.size > marked) {
        Durability.persistLanded(batch);
      }
    }
  }

  // The batch is in the overlay from the moment it opens, so a write is readable on the next line
  // of the action that made it.
  // How long the oldest unsent batch has been waiting, named by its sequence number - null when no
  // pending batch has a number yet.
  static oldestPendingSeq() {
    return Batches.pending[0]?.seq ?? null;
  }

  static pendingCount() {
    return Batches.pending.length;
  }

  // The refused batches as something a person can read: the reason INSPECTED rather than boxed,
  // so a devtools panel and a browser-driven test can both take it through JSON. Step 10's queue
  // surface hands Elixir the term itself - this is the window that exists before it does.
  static rejectedSummaries() {
    return Batches.rejected.map((batch) => ({
      reason: Interpreter.inspect(batch.reason),
      rows: Array.from(batch.rowKeys()),
      seq: batch.seq,
      write: batch.write,
    }));
  }

  // Stamped with its user here rather than at seal: an action can be suspended across a login, and
  // what it wrote before and after that is still the work of the user who started it.
  static open(target) {
    const batch = new Batch(target);

    batch.actorUserId = LocalDatabase.actorUserId ?? null;
    batch.actorUserChanges = LocalDatabase.actorUserChanges;

    Batches.#running = batch;
    Overlay.push(batch);

    return batch;
  }

  // Drops the overlay's batches too: forgetting them here while it went on folding them would
  // leave writes on the screen that nothing could ever confirm or take back.
  static reset() {
    Batches.#clearRetry();

    Batches.#filing.clear();
    Batches.#releasedOpen.clear();
    Batches.#setAside.clear();
    Batches.#filingAside.clear();
    Batches.#asideOrder.clear();
    Batches.pending = [];
    Batches.rejected = [];
    Batches.#answered = new Set();
    Batches.#retryAttempts = 0;
    Batches.#running = null;
    Batches.#seq = 0;

    Overlay.reset();
  }

  // What an answer does to the batch it names, wherever that batch is held.
  //
  // Written once and reached two ways: by the tab that sent the batch, and by every other tab of
  // the browser, which holds the same batch and is told the verdict. A tab that does not hold it -
  // one that never took it up, or took it up and has already settled it - only keeps the number,
  // so the message announcing that batch doesn't bring it back if it arrives after this.
  //
  // Named by NUMBER rather than by the batch, because the batch a message reaches is not the object
  // the sender holds: it is that tab's own copy, built from the same record.
  static settle(seq, answer) {
    Batches.#answered.add(seq);

    const batch = Batches.pending.find((held) => held.seq === seq);

    if (batch === undefined) {
      return;
    }

    Batches.pending = Batches.pending.filter((held) => held !== batch);

    // Answered, so the server is answering: the next failure starts the backoff from the beginning
    // rather than from wherever the last run of failures left it.
    Batches.#retryAttempts = 0;

    if (answer.status === "confirmed") {
      // No place and not everything marked is a client waiting for a fill or part way through one,
      // or a tab the server stopped, whose row then just stays unstored.
      Overlay.promote(batch, answer.kept, {
        dropped: answer.dropped,
        fillPending:
          SyncStream.syncCursor === null && !LocalDatabase.isAllSynced(),
      });
    } else {
      Batches.#reject(batch, answer);
    }

    SyncStream.scheduleRender();
  }

  // Where the previous page load's numbering got to, so this one counts on from there - or where the
  // store's got to, for a tab moving to another user's group (see DataLayer.followIdentity). Never
  // backwards: a number is identified with its replica, and the server answers a repeat from its
  // record of the first batch to carry it.
  //
  // The counter moves in THIS tab's memory while being stored once per browser, so two tabs that
  // resume from the same number can hand out the same next one - and the server, seeing the pair
  // twice, answers the second with the first one's verdict rather than applying it. Known and
  // deliberate for as long as one identity per browser means an unlocked counter: the multi-tab
  // work takes the number inside the same lock that puts the batch in the shared queue, which
  // removes the case rather than detecting it.
  static resumeFrom(seq) {
    Batches.#seq = Math.max(Batches.#seq, seq);
  }

  // The number a batch ships under, and its place in the queue once it has one.
  //
  // Where there is a store, the store gives it: read and spent inside the transaction that files
  // the batch, so two tabs cannot take one number. Where there is not - private browsing, a browser
  // that cannot store - this tab counts for itself, which is what it did everywhere before there
  // was anywhere to file a batch, and is safe for the same reason it was then: nothing is shared.
  //
  // `#seq` is what this tab has SEEN rather than what it has spent: it follows a number the store
  // handed out, so a tab that later has to count for itself counts on from there.
  static #number(batch) {
    const filing = Durability.fileBatch(batch);

    // Where there is nowhere to file it the number is taken HERE, in the turn the batch was
    // closed, rather than in the one the filing settles - so a batch closed where nothing can be
    // stored has its number the moment the action ends, exactly as it did before there was
    // anywhere to file one. A store that failed on the spot counts: it's in memory mode by now, and
    // the batch keeps its place ahead of whatever the action closes next.
    if (Durability.mode === "memory") {
      batch.filed = false;

      Batches.#numbered(batch);

      return filing;
    }

    return filing.then((stored) => {
      batch.filed = stored;

      if (stored && Batches.#disowned.has(batch)) {
        Batches.#letGo(batch);
      } else {
        Batches.#numbered(batch);
      }
    });
  }

  // The batches the store holds, off this tab's queue and screen, for a tab that can no longer send
  // them. The next page load does.
  static #letFiledGo() {
    Batches.disown();
    SyncStream.scheduleRender();
  }

  // A batch disown() couldn't decide about, now known to be in the store. Its number stays seen,
  // like those of the batches disown() let go of at once.
  //
  // Its rows may not come back through this tab's stream as disown() says: the leader may have let
  // go of the store before reading this batch, and then it waits for the next page load to send
  // it. Kept on screen instead, a move the leader did send would show twice, since this tab has
  // left the group and would never hear the answer.
  static #letGo(batch) {
    Batches.#seq = Math.max(Batches.#seq, batch.seq);
    Batches.pending = Batches.pending.filter((held) => held !== batch);

    Overlay.remove(batch);
    SyncStream.scheduleRender();
  }

  // A batch whose number is settled: taken from this tab's own count if the store gave none, and
  // followed by `#seq` either way, so a tab that later has to count for itself counts on from the
  // highest number it has seen rather than from the last one it spent.
  //
  // Except in a page that has had a store, until the server has minted it a pair of its own. Any
  // other pair it presents can be one the store holds, or is about to, and a number spent under it
  // would be recorded nowhere: the next load could spend it again on another write, and the server
  // would answer that write from this one's record. So the batch waits, unnumbered and behind
  // every stored batch, for that pair (see flush).
  //
  // And under that pair it waits for the batches made before it, whose filings can still fail and
  // need a number too. Numbers are the order batches go out in, and a later batch may name a row an
  // earlier one created.
  static #numbered(batch) {
    if (batch.seq === null) {
      if (Durability.hadStore && !Batches.#isNextToNumber(batch)) {
        return;
      }

      batch.seal(++Batches.#seq);
    } else {
      Batches.#seq = Math.max(Batches.#seq, batch.seq);
    }

    Batches.#sort();

    // The other tabs of this browser take it up and show it, and the one that sends sends it -
    // which is what puts a write made in one tab on the screen of the next before the server has
    // heard of it. As the RECORD, because that is what a tab rebuilds a batch from whether it
    // reads it here or out of the store, and because a Batch is not something a browser can carry
    // from one tab to another.
    //
    // Not one of a user this tab no longer serves: a tab that hasn't heard of the change yet would
    // take it up and send it under the new session.
    //
    // Nor one the store never got: its number was never written down, so the store can hand it
    // to another batch, and a tab sending it under the group's pair would have the server answer
    // that batch from this one's record. And this tab keeps it to send under its own pair (see
    // disown), so the server would apply it twice.
    if (
      batch.filed !== false &&
      batch.actorUserId === (LocalDatabase.actorUserId ?? null)
    ) {
      Tabs.post({kind: "sealed", record: batch.record()});
    }
  }

  // Only the ones the store never got. One whose filing is still in flight is decided when it
  // settles, unless its owner is signed in again by then and took it back (see #filingAside).
  static #putAside(batches) {
    for (const batch of batches) {
      // The retry that would end its wait reaches only the batches the tab sends, and its owner is
      // back in another session, which the newest pair can cure.
      batch.switchedPair = false;

      if (batch.filed !== true && !Batches.#asideOrder.has(batch)) {
        Batches.#asideOrder.set(batch, Batches.#asideCount++);
      }

      if (batch.filed === false) {
        if (!Batches.#setAside.has(batch.actorUserId)) {
          Batches.#setAside.set(batch.actorUserId, []);
        }

        Batches.#setAside.get(batch.actorUserId).push(batch);
      } else if (batch.filed === null) {
        const owner = batch.actorUserId;

        if (!Batches.#filingAside.has(owner)) {
          Batches.#filingAside.set(owner, []);
        }

        Batches.#filingAside.get(owner).push(batch);

        batch.recorded.then(() => {
          const waiting = Batches.#filingAside.get(owner) ?? [];

          // Back already, or decided by an earlier change of user.
          if (!waiting.includes(batch)) {
            return;
          }

          if (waiting.length === 1) {
            Batches.#filingAside.delete(owner);
          } else {
            waiting.splice(waiting.indexOf(batch), 1);
          }

          if (batch.filed === false) {
            Batches.#putAside([batch]);
            Batches.releaseForeign(LocalDatabase.actorUserId);
            Batches.flush();
          } else {
            Batches.#asideOrder.delete(batch);
          }
        });
      }
    }
  }

  static #trackFiling(batch) {
    const filed = () => Batches.#filing.delete(batch);

    Batches.#filing.add(batch);
    batch.recorded.then(filed, filed);
  }

  static #isNextToNumber(batch) {
    return (
      Replica.minted &&
      Batches.pending.find(
        (held) => held.seq === null || held.filed === null,
      ) === batch
    );
  }

  // Oldest first, which is the order batches must ship in - a later batch may name a row an earlier
  // one created. A batch still waiting for its number sits at the TAIL, and cannot be wrong there:
  // whatever number it gets will be above every number already spent.
  static #sort() {
    Batches.pending.sort((left, right) => {
      if (left.seq === right.seq) {
        return 0;
      }

      if (left.seq === null) {
        return 1;
      }

      if (right.seq === null) {
        return -1;
      }

      return left.seq - right.seq;
    });
  }

  // What a read of the store found, taken up and told to the other tabs, which may never hear of
  // it from the tab that filed it. Only what's new, because a queue retrying while offline reads
  // the store every few seconds.
  static #takeUp(records) {
    const held = new Set(Batches.pending);

    Batches.adopt(records);

    for (const batch of Batches.pending) {
      if (!held.has(batch)) {
        Tabs.postNow({kind: "sealed", record: batch.record()});
      }
    }
  }

  // For a queue that is about to stop, which doesn't drain down to what's above its head.
  static async #takeUpWhileHeld() {
    Batches.#takeUp(await Durability.queuedBatches());
  }

  // A network failure and a status carrying no verdict are the same thing to this loop: nobody
  // said anything about the writes. A malformed envelope is NOT - that is this client's own bug,
  // and it is raised rather than retried forever.
  static async #answerFor(batch) {
    try {
      return await Mutations.send(batch);
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        batch.mark("pending");

        throw error;
      }

      return {httpStatus: error.message, status: "failed"};
    }
  }

  // Whether the server refused a batch because this bundle was built against another model.
  static #refusesBuild(answer) {
    if (answer.status !== "rejected") {
      return false;
    }

    const reason = Deserializer.deserialize(answer.reason);

    return Type.isAtom(reason) && reason.value === "stale_build";
  }

  static #clearRetry() {
    if (Batches.#retryTimer !== null) {
      clearTimeout(Batches.#retryTimer);
      Batches.#retryTimer = null;
    }

    Batches.#retryFor = null;
  }

  // The rows the given batches create of the given types that the base doesn't hold, each keyed
  // "<type> <id>". A create a frame already landed counts too: the frame told the client to drop
  // the row, or delivered it and the row has left since, and the batch's edges pointing at it have
  // yet to be passed over.
  static #unsentCreates(batches, types) {
    const unsent = new Set();

    for (const batch of batches) {
      for (const write of batch.writes) {
        if (
          write.op === "create" &&
          types.has(write.type) &&
          LocalDatabase.baseRow(write.type, write.id) === null
        ) {
          unsent.add(`${write.type} ${write.id}`);
        }
      }
    }

    return unsent;
  }

  // Whether the write is an edge whose target is one of the given rows, keyed "<type> <id>".
  static #pointsAtAny(write, rowKeys) {
    if (write.target_id === undefined || !Model.isEntityType(write.type)) {
      return false;
    }

    const relationship = Model.relationships(write.type)[write.relationship];

    return (
      relationship !== undefined &&
      rowKeys.has(`${relationship.type} ${write.target_id}`)
    );
  }

  // A refused batch takes its rows with it - a created row vanishes, an updated one reverts -
  // and what is left is the reason, on the batch, for the queue surface to show. The row carries
  // nothing: a rejected create has no row left to carry a state, and a rejected update's row is
  // the server's again.
  static #reject(batch, answer) {
    Overlay.remove(batch);

    batch.mark("rejected");

    // Read HERE and nowhere earlier: the reason is a term the server serialized, and the answer
    // carrying it stays a plain JSON value until it reaches the one reader that needs the term
    // itself.
    batch.reason = Deserializer.deserialize(answer.reason);

    batch.write = answer.write;

    Batches.rejected.push(batch);
  }

  // The one wake-up that needs nothing to happen. The stream is up, so no reconnect is coming, and
  // the user is idle, so no action is - and without this a batch would sit unsent while the page
  // looked perfectly healthy, for as long as the user left it alone.
  //
  // The DELAY IS THE STREAM'S, not one of this module's own. How eagerly this client retries a
  // server that is not answering is one policy, already argued and bounded where the stream
  // defines it, and a second set of numbers here would be a second answer to the same question.
  static #scheduleRetry(switched = null) {
    Batches.#clearRetry();

    Batches.#retryFor = switched;

    Batches.#retryTimer = setTimeout(() => {
      Batches.#retryTimer = null;
      Batches.#retryFor = null;

      // The wait a refused switch was held to is over (see flush).
      for (const batch of Batches.pending) {
        batch.switchedPair = false;
      }

      Batches.flush();
    }, Sse.computeReconnectDelay(++Batches.#retryAttempts));
  }
}

"use strict";

import Batch from "./batch.mjs";
import Client from "./client.mjs";
import Clock from "./clock.mjs";
import Durability from "./durability.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import Overlay from "./overlay.mjs";
import Replica from "./replica.mjs";
import Sse from "./sse.mjs";
import Tabs from "./tabs.mjs";

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

  // The batch of the action running right now, and nothing when no action is - a write outside an
  // action has nowhere to belong.
  // The tries a batch nobody answered has had so far, which is what the next delay is computed
  // from. Back to nothing the moment any batch is answered - a server that is answering again
  // has earned the short delay, whatever it cost to reach it.
  static #retryAttempts = 0;

  // The retry waiting to fire, and nothing while none is. Not cleared by the other wake-ups, and
  // deliberately: a run of the loop ends either with the queue empty or with a retry it has just
  // rescheduled itself, so a timer left standing by an earlier run never finds work - it is the
  // guard and the empty queue that make it harmless, and a clear on every entry would be a line
  // nothing could ever observe.
  static #retryTimer = null;

  static #running = null;

  // One batch is in flight at a time, and the loop that keeps it that way must not be entered
  // twice - every close calls flush, and an answer can arrive while another action is running.
  static #sending = false;

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
  // otherwise be folded and sent twice. A batch of ANOTHER user is left where it is, since the
  // server applies a batch under the user of the session that sends it, and the page mounted under
  // its owner is what will take it up. And in both cases the counter still follows it: `#seq` is
  // what this tab has SEEN, so a number spent by another tab is a number this one will not spend.
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

      if (held || record.actorUserId !== owner) {
        continue;
      }

      const batch = Batch.fromRecord(record);

      for (const write of batch.writes) {
        if (write.stamp) {
          Clock.observe(write.stamp);
        }
      }

      Batches.pending.push(batch);
      Overlay.push(batch);

      taken = true;
    }

    if (taken) {
      Batches.#sort();
      Sse.scheduleRender();
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

    if (batch.writes.length === 0) {
      Overlay.remove(batch);

      return null;
    }

    // Whose work this is, taken at seal rather than at send: a batch outlives the page that made
    // it, and the page that eventually sends it may belong to somebody else. Only a page mounted
    // under this user will take it up again.
    batch.actorUserId = LocalDatabase.actorUserId ?? null;

    batch.mark("pending");

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

  // Every batch this tab is holding, let go: out of the queue, so this tab does not send it, and
  // out of the overlay, so nothing is shown that this tab can no longer learn the fate of.
  //
  // For a tab whose group has DISSOLVED. Those batches were numbered under the group's identity,
  // the tab that kept that identity is still sending them, and this one - which has just taken a
  // fresh identity of its own - would be sending a second copy of each under a number nothing has
  // recorded against it. The server would apply them twice.
  //
  // The rows go back to what the server last said, and come back when its answer to those batches
  // does, through this tab's own stream, as an ordinary frame. That gap is what a store breaking
  // mid-session costs a tab that was not the one sending.
  static disown() {
    for (const batch of Batches.pending) {
      Overlay.remove(batch);
    }

    Batches.pending = [];
  }

  // Everything the action wrote goes away, which is what a raise has to mean: an action's writes
  // land together or not at all, and dropping the layer is the whole of putting them back.
  static discard() {
    const batch = Batches.#running;

    if (batch !== null) {
      Batches.#running = null;

      Overlay.remove(batch);
    }

    return batch;
  }

  // Sends the pending batches, oldest first, ONE AT A TIME. The ordering is not politeness: a
  // later batch may name a row an earlier one created, and its based_on for a column an earlier
  // one wrote is that batch's own stamp - so overlapping them turns a sound chain into a refusal.
  static async flush() {
    // ONE TAB OF A BROWSER SENDS, and it is the one holding the group's lock. A batch made in any
    // tab is filed in the one queue they share, so the leader's own reading of that queue is what
    // ships - and a follower that sent as well would put a second copy of every batch on the wire,
    // under the same replica and number, for the server to answer twice from one record.
    if (!Tabs.leader || Batches.#sending) {
      return;
    }

    Batches.#sending = true;

    try {
      while (true) {
        // The queue as the STORE holds it, before every send rather than once: any tab can file a
        // batch, and the message saying so can be missed by a tab that was starting up or never
        // sent at all by a tab that closed straight after filing. Reading it back is reading it in
        // number order, so what ships is the order the batches were made in whatever order this
        // tab heard about them.
        Batches.adopt(await Durability.batchesAbove(Batches.#seq));

        const batch = Batches.pending[0];

        if (batch === undefined) {
          return;
        }

        // Before anything leaves: a batch may not be answered under a number this browser could
        // hand out again after a reload.
        await batch.recorded;

        batch.mark("sending");

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
          // Once per page load. `refresh` answers false when the fresh pair is already the one in
          // use, which is the case where the session changed after this page loaded and there is
          // nothing here that can help.
          //
          // AWAITED, the same discipline the counter's write gets and for the same reason: nothing
          // is sent under an identity that is not recorded. Fired and forgotten, a reload landing
          // before the write commits would take up the REFUSED pair again while the counter had
          // moved on - and the batch that followed would be refused a second time before this path
          // could recover it.
          if (answer.httpStatus === 403 && Replica.refresh()) {
            await Durability.persistReplica(Replica.current());

            Sse.reconnect();

            continue;
          }

          batch.mark("pending");

          console.warn(
            `Hologram: batch ${batch.seq} was not answered (${answer.httpStatus}) - it stays pending and goes again shortly, on the next write, or on reconnect`,
          );

          Batches.#scheduleRetry();

          return;
        }

        // A verdict is a verdict, whichever way it went: nothing is waiting on this batch any
        // more, and a later page load has no reason to take it up. Confirmed and refused alike -
        // including the two refusals that judge the BUILD and the STAMPS rather than the writes
        // (`:stale_build`, `:clock`), which the server does not record and would evaluate afresh
        // on a resend. Keeping one for that resend was weighed and refused (D5): the rows are off
        // the screen already, so a batch kept would come back days later as a write the user
        // watched fail, and a device whose clock is permanently wrong would resend it on every
        // page load with nothing in v1 able to discard it.
        Durability.forgetBatch(batch.seq);

        // Every tab of the group holds this batch and every one of them has to let it go - the
        // answer reaches them as it arrived, undecoded, because a client term is not something a
        // browser can carry from one tab to another.
        Tabs.post({answer, kind: "answered", seq: batch.seq});

        Batches.settle(batch.seq, answer);
      }
    } finally {
      Batches.#sending = false;
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
  // BEFORE it reads the answer, so a refused batch leaves with the answer that refused it. While
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

  // The batch is in the overlay from the moment it opens, so a write is readable on the next line
  // of the action that made it.
  // How long the oldest unsent batch has been waiting, named by its sequence number - null when
  // nothing is pending.
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

  static open(target) {
    const batch = new Batch(target);

    Batches.#running = batch;
    Overlay.push(batch);

    return batch;
  }

  // Drops the overlay's batches too: forgetting them here while it went on folding them would
  // leave writes on the screen that nothing could ever confirm or take back.
  static reset() {
    Batches.#clearRetry();

    Batches.pending = [];
    Batches.rejected = [];
    Batches.#retryAttempts = 0;
    Batches.#running = null;
    Batches.#seq = 0;

    Overlay.reset();
  }

  // What an answer does to the batch it names, wherever that batch is held.
  //
  // Written once and reached two ways: by the tab that sent the batch, and by every other tab of
  // the browser, which holds the same batch and is told the verdict. A tab that does not hold it -
  // one that never took it up, or took it up and has already settled it - has nothing to do.
  //
  // Named by NUMBER rather than by the batch, because the batch a message reaches is not the object
  // the sender holds: it is that tab's own copy, built from the same record.
  static settle(seq, answer) {
    const batch = Batches.pending.find((held) => held.seq === seq);

    if (batch === undefined) {
      return;
    }

    Batches.pending = Batches.pending.filter((held) => held !== batch);

    // Answered, so the server is answering: the next failure starts the backoff from the beginning
    // rather than from wherever the last run of failures left it.
    Batches.#retryAttempts = 0;

    if (answer.status === "confirmed") {
      Overlay.promote(batch, answer.kept);
    } else {
      Batches.#reject(batch, answer);
    }

    Sse.scheduleRender();
  }

  // Where the previous page load's numbering got to, so this one counts on from there. Never
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
    Batches.#seq = seq;
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
    const filed = Durability.fileBatch(batch);

    // Where there is nowhere to file it the number is taken HERE, in the turn the batch was
    // closed, rather than in the one the filing settles - so a batch closed where nothing can be
    // stored has its number the moment the action ends, exactly as it did before there was
    // anywhere to file one.
    if (Durability.mode === "memory") {
      Batches.#numbered(batch);

      return filed;
    }

    return filed.then(() => Batches.#numbered(batch));
  }

  // A batch whose number is settled: taken from this tab's own count if the store gave none, and
  // followed by `#seq` either way, so a tab that later has to count for itself counts on from the
  // highest number it has seen rather than from the last one it spent.
  static #numbered(batch) {
    if (batch.seq === null) {
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
    Tabs.post({kind: "sealed", record: batch.record()});
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

  // A network failure and a status carrying no verdict are the same thing to this loop: nobody
  // said anything about the writes. A malformed envelope is NOT - that is this client's own bug,
  // and it is raised rather than retried forever.
  static async #answerFor(batch) {
    try {
      return await Client.sendMutation(batch);
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        batch.mark("pending");

        throw error;
      }

      return {httpStatus: error.message, status: "failed"};
    }
  }

  static #clearRetry() {
    if (Batches.#retryTimer !== null) {
      clearTimeout(Batches.#retryTimer);
      Batches.#retryTimer = null;
    }
  }

  // A refused batch takes its rows with it - a created row vanishes, an updated one reverts -
  // and what is left is the reason, on the batch, for the queue surface to show. The row carries
  // nothing: a rejected create has no row left to carry a state, and a rejected update's row is
  // the server's again.
  static #reject(batch, answer) {
    Overlay.remove(batch);

    batch.mark("rejected");

    // Read HERE and nowhere earlier: the reason is a client term the server encoded, and the
    // answer carrying it stays a plain JSON value until it reaches the one reader that needs the
    // term itself.
    batch.reason = Interpreter.evaluateJavaScriptExpression(answer.reason);

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
  static #scheduleRetry() {
    Batches.#clearRetry();

    Batches.#retryTimer = setTimeout(() => {
      Batches.#retryTimer = null;

      Batches.flush();
    }, Sse.computeReconnectDelay(++Batches.#retryAttempts));
  }
}

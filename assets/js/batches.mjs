"use strict";

import Batch from "./batch.mjs";
import Client from "./client.mjs";
import Durability from "./durability.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import Overlay from "./overlay.mjs";
import Sse from "./sse.mjs";

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
  static #running = null;

  // One batch is in flight at a time, and the loop that keeps it that way must not be entered
  // twice - every close calls flush, and an answer can arrive while another action is running.
  static #sending = false;

  static #seq = 0;

  // An action that awaits stops running, and another action may run to completion before it comes
  // back - so the batch it opened is taken out of the slot here and put back in the turn it
  // resumes, before any of its remaining code runs. Task.await/1 is the only place an action stops:
  // every JS promise reaching Elixir is boxed as a Task, and nothing else unwraps one.
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

    batch.seal(++Batches.#seq);

    // Started here and awaited by the sender, so the number is on its way down while the action's
    // own render happens - the store is never on the path of what the user sees.
    batch.recorded = Durability.persistCounter(Batches.#seq);

    Batches.pending.push(batch);

    return batch;
  }

  static current() {
    return Batches.#running;
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
    if (Batches.#sending || Batches.pending.length === 0) {
      return;
    }

    Batches.#sending = true;

    try {
      while (Batches.pending.length > 0) {
        const batch = Batches.pending[0];

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
        // (replica_id, seq) is answered from the record rather than applied twice. The wake-ups
        // are the next action's close and the connection coming back - no timer, since neither a
        // base delay nor a cap has a bound anyone can state yet.
        if (answer.status === "failed") {
          batch.mark("pending");

          console.warn(
            `Hologram: batch ${batch.seq} was not answered (${answer.httpStatus}) - it stays pending and goes again on the next write or reconnect`,
          );

          return;
        }

        Batches.pending.shift();

        if (answer.status === "confirmed") {
          Overlay.promote(batch, answer.kept);
        } else {
          Batches.#reject(batch, answer);
        }

        Sse.scheduleRender();
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
      if (batch.seq <= appliedSeq) {
        batch.land(rowKeys);
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
    Batches.pending = [];
    Batches.rejected = [];
    Batches.#running = null;
    Batches.#seq = 0;

    Overlay.reset();
  }

  // Where the previous page load's numbering got to, so this one counts on from there. Never
  // backwards: a number is identified with its replica, and the server answers a repeat from its
  // record of the first batch to carry it.
  static resumeFrom(seq) {
    Batches.#seq = seq;
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

  // A refused batch takes its rows with it - a created row vanishes, an updated one reverts -
  // and what is left is the reason, on the batch, for the queue surface to show. The row carries
  // nothing: a rejected create has no row left to carry a state, and a rejected update's row is
  // the server's again.
  static #reject(batch, answer) {
    Overlay.remove(batch);

    batch.mark("rejected");
    batch.reason = answer.reason;
    batch.write = answer.write;

    Batches.rejected.push(batch);
  }
}

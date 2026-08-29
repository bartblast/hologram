"use strict";

import Batch from "./batch.mjs";
import Client from "./client.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Overlay from "./overlay.mjs";
import Sse from "./sse.mjs";

// Which batch an action's writes go to, and what becomes of it when the action ends.
//
// An action opens one on the way in and closes it on the way out, so "the writes of one action"
// needs no bookkeeping from the app: a write goes to whichever batch is open. A batch that
// collected nothing is dropped rather than sent, and one that collected something is sealed, takes
// the next sequence number and joins the queue in the order it was made.
//
// That order is the order it ships, and the ordering is load-bearing rather than tidy: a later
// batch may name a row an earlier one created, and its based_on for a column an earlier one wrote
// is that batch's own stamp. Shipping them out of order turns a sound chain into a refusal.
//
// Open batches are a STACK rather than one slot, because an action that awaits can still be open
// when another starts. Two genuinely overlapping actions can therefore put a write on the other's
// batch - both still ship and nothing is lost, but the "one action, one batch" boundary blurs.
// Recorded rather than solved: the answer is a context per action, which arrives with the client's
// own process model.
export default class Batches {
  // Sealed and waiting to ship, oldest first.
  static pending = [];

  // Refused by the server, holding what it said. The queue surface an app can list, and the
  // devtools inspector, are the readers.
  //
  // TODO: filled when the sender loop records a refusal.
  static rejected = [];

  // One batch is in flight at a time, and the loop that keeps it that way must not be entered
  // twice - every close calls flush, and an answer can arrive while another action is running.
  static #sending = false;

  static #seq = 0;

  static #stack = [];

  // Seals the batch the action opened, or drops it when the action wrote nothing - a sequence
  // number is spent only by a batch that will ship. Answers the sealed batch, or nothing when
  // there was nothing to seal.
  static close() {
    const batch = Batches.#stack.pop();

    if (batch === undefined) {
      return null;
    }

    if (batch.writes.length === 0) {
      Overlay.remove(batch);

      return null;
    }

    batch.seal(++Batches.#seq);
    Batches.pending.push(batch);

    return batch;
  }

  static current() {
    return Batches.#stack.at(-1) ?? null;
  }

  // Everything the action wrote goes away, which is what a raise has to mean: an action's writes
  // land together or not at all, and dropping the layer is the whole of putting them back.
  static discard() {
    const batch = Batches.#stack.pop() ?? null;

    if (batch !== null) {
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
          Overlay.promote(batch, answer.dropped);
        } else {
          Batches.#reject(batch, answer);
        }

        Sse.scheduleRender();
      }
    } finally {
      Batches.#sending = false;
    }
  }

  // The batch is in the overlay from the moment it opens, so a write is readable on the next line
  // of the action that made it.
  static open(target) {
    const batch = new Batch(target);

    Batches.#stack.push(batch);
    Overlay.push(batch);

    return batch;
  }

  // Drops the overlay's batches too: forgetting them here while it went on folding them would
  // leave writes on the screen that nothing could ever confirm or take back.
  static reset() {
    Batches.pending = [];
    Batches.rejected = [];
    Batches.#seq = 0;
    Batches.#stack = [];

    Overlay.reset();
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

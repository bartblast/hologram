"use strict";

import Batch from "./batch.mjs";
import Overlay from "./overlay.mjs";

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

  // TODO: sends the pending batches, one at a time and in order, and records what the server
  // answers for each.
  static flush() {
    return null;
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
}

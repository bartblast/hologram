"use strict";

// One action's writes, from the moment the action opens it until the server answers.
//
// The batch is the unit everything downstream is counted in: one envelope, one server
// transaction, one place in the pending queue, and one overlay layer whose rows read as applied
// for as long as it is there. It holds the wire objects themselves rather than a form of its own,
// so the array folded over the base rows here is the array posted to the endpoint - there is one
// spelling of a write in the system, and no step that could translate it wrongly.
export default class Batch {
  // What the server refused and which write it named, both as its answer spells them. A batch
  // that was never refused carries neither.
  //
  // TODO: filled when the sender loop records the server's answer.
  reason = null;

  // Taken at seal rather than at open: a number is spent in the order batches SHIP, and an action
  // that writes nothing never spends one.
  seq = null;

  // "open" while its action runs, "pending" once sealed, "sending" while in flight, "rejected"
  // once refused. There is no "confirmed": a confirmed batch is promoted into the base rows and
  // dropped, so nothing is left to hold a state.
  state = "open";

  // The cid of the component whose action opened it, so what the server says about these writes
  // can be delivered where they were made.
  target = null;

  // TODO: filled when the sender loop records the server's answer.
  write = null;

  writes = [];

  constructor(target) {
    this.target = target;
  }

  append(write) {
    this.writes.push(write);
  }

  mark(state) {
    this.state = state;
  }

  // The rows this batch has anything to say about, spelled the way the database's own carried
  // marks are - what the overlay asks in order to fold a row, and what a row's durability is
  // derived from. An edge names its SOURCE row, which is the row whose relationships changed.
  rowKeys() {
    return new Set(this.writes.map((write) => `${write.type} ${write.id}`));
  }

  seal(seq) {
    this.seq = seq;
    this.state = "pending";
  }
}

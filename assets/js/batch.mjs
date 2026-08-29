"use strict";

// One action's writes, from the moment the action opens it until the server answers.
//
// The batch is the unit everything downstream is counted in: one envelope, one server
// transaction, one place in the pending queue, and one overlay layer whose rows read as applied
// for as long as it is there. It holds the wire objects themselves rather than a form of its own,
// so the array folded over the base rows here is the array posted to the endpoint - there is one
// spelling of a write in the system, and no step that could translate it wrongly.
export default class Batch {
  // What the server refused, as its answer spells it - a decoded client term. A batch that was
  // never refused carries none. Nothing app-facing reads it yet: a rejection after the client has
  // navigated away arrives when the component's page bundle is not even loaded, so the channel
  // that can always reach app code is a handler in the runtime bundle, and that is step 10's to
  // build beside the durable queue that makes it meaningful.
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

  // Which write a refusal named, by its index in `writes` - null for a refusal of the whole
  // batch, which is what a stale build or a clock too far ahead gets.
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

  // The rows this batch has anything to say about, each keyed "<type> <id>" - what the overlay
  // asks in order to fold a row. A space tells the two halves apart safely because neither an
  // entity type's name nor an id can contain one. An edge names its SOURCE row, which is the row
  // whose relationships changed.
  rowKeys() {
    return new Set(this.writes.map((write) => `${write.type} ${write.id}`));
  }

  seal(seq) {
    this.seq = seq;
    this.state = "pending";
  }
}

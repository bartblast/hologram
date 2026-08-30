"use strict";

// One action's writes, from the moment the action opens it until the server answers.
//
// The batch is the unit everything downstream is counted in: one envelope, one server
// transaction, one place in the pending queue, and one overlay layer whose rows read as applied
// for as long as it is there. It holds the wire objects themselves rather than a form of its own,
// so the array folded over the base rows here is the array posted to the endpoint - there is one
// spelling of a write in the system, and no step that could translate it wrongly.
export default class Batch {
  // Who was signed in on the page that sealed this batch, and nothing at all for a visitor.
  //
  // A batch outlives the page that made it, so what is kept of one has to say whose work it is:
  // the server applies a batch under the user of the session that SENDS it, so a batch taken up
  // by a page somebody else has since signed in on would be written in their name. Alice's note
  // would become Bob's.
  actorUserId = null;

  // The writes whose effect the base already holds, by their position in `writes`. A frame naming
  // this batch's number is what puts one here: the server applied it, resolved it against
  // whatever else had moved, and sent back the row it left - so folding the write on top again
  // would be applying the same change twice, which for a moved counter means counting it twice.
  //
  // The wire object itself is untouched, so a batch that has to be sent again ships exactly what
  // it always would. And the batch goes on NAMING the row until the answer arrives: it is still
  // pending, still the user's unanswered work, and only the fold passes over it.
  landed = new Set();

  // What the server refused, as its answer spells it - a decoded client term. A batch that was
  // never refused carries none. Nothing app-facing reads it yet: a rejection after the client has
  // navigated away arrives when the component's page bundle is not even loaded, so the channel
  // that can always reach app code is a handler in the runtime bundle, and that is step 10's to
  // build beside the durable queue that makes it meaningful.
  reason = null;

  // The write that put this batch's number down, which the sender waits on before shipping it. A
  // number is spent only once it is STORED: handed out and not written, the next page load hands
  // out the same one, and the server - which answers a number it has already seen from its record
  // rather than applying it again - answers that batch with the verdict this one got.
  //
  // Already settled where there is nowhere to store, so the wait costs a browser without durable
  // storage nothing at all.
  recorded = Promise.resolve();

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

  // A batch as it was sealed, out of what was kept of it. Pending by construction: a batch that
  // was kept is a batch nothing has answered.
  //
  // It carries no target. The cid of a component on a page that has since been torn down names
  // nothing in the page running now, and reading one would be worse than having none.
  //
  // `recorded` is left as the settled promise it starts as, which is true rather than convenient:
  // this batch is already written down, so there is nothing to wait for before it ships.
  static fromRecord(record) {
    const batch = new Batch(null);

    batch.actorUserId = record.actorUserId;
    batch.landed = new Set(record.landed);
    batch.writes = record.writes;

    batch.seal(record.seq);

    return batch;
  }

  isLanded(index) {
    return this.landed.has(index);
  }

  // Marks every write naming one of the given rows as already in the base. Called with what a
  // frame just wrote, per row rather than per batch: one batch's writes can reach two windows and
  // arrive as two frames, and marking the second row's write on the first frame would take it off
  // the screen until its own frame caught up.
  //
  // Answers whether anything was marked that was not marked already. Most frames name rows no
  // pending batch has anything to say about, and a mark that did not move is not worth writing
  // down.
  land(rowKeys) {
    const marked = this.landed.size;

    this.writes.forEach((write, index) => {
      if (rowKeys.has(`${write.type} ${write.id}`)) {
        this.landed.add(index);
      }
    });

    return this.landed.size > marked;
  }

  mark(state) {
    this.state = state;
  }

  // What is kept of this batch, and the whole of what a later page load rebuilds it from.
  //
  // THE SHAPE IS FROZEN. A bundle reads what an older bundle wrote - a deploy that changes the
  // model leaves the old model's database standing with its unsent batches in it, and draining
  // that is a later step's - so a field is added only with a reader that tolerates its absence,
  // and none is ever renamed or given a second meaning.
  //
  // Four things, each here because rebuilding without it would be wrong: the writes, which are
  // what gets sent; the number, which identifies the batch and is the order it ships in; who made
  // it, which decides who may send it; and which of its writes the base already holds, without
  // which a moved counter is added a second time on the next load.
  record() {
    return {
      actorUserId: this.actorUserId,
      landed: Array.from(this.landed).sort((left, right) => left - right),
      seq: this.seq,
      writes: this.writes,
    };
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

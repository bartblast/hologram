"use strict";

import Clock from "./clock.mjs";
import Model from "./model.mjs";

// The writes this client has made and the server has not answered yet, folded over the rows the
// server sent.
//
// The base is what LocalDatabase holds, and only frames and page-carried rows write it. A batch
// sits on top as the writes themselves, and every read of a row passes through here on its way
// out - so a row reads as its writer left it while the row underneath stays exactly what the
// server last said. That is what lets a rejection put things back by DROPPING A LAYER rather than
// by undoing anything, and what lets a frame land under a pending write without disturbing it.
//
// Folding is the same rule the server merges by, which is the point: re-applying a batch onto a
// base that has moved is this function again, not a re-run of anything.
export default class Overlay {
  // Open and pending batches, in the order they were made - which is the order they will ship, and
  // so the order their effects stack.
  static #batches = [];

  // Whether any pending write names this row - "applied" for as long as one does, "confirmed" once
  // none does. A row never reads as rejected: a refused batch is dropped, and what is left is the
  // server's row.
  static durability(type, id) {
    return Overlay.names(type, id) ? "applied" : "confirmed";
  }

  // The row as the pending writes leave it, or the base itself when none names it - the same
  // object in that case, because the overwhelming majority of reads are of rows nothing is pending
  // for, and a copy per read would cost the whole database on every render.
  static foldRow(type, id, base) {
    if (!Overlay.names(type, id)) {
      return base;
    }

    let row = base;

    for (const batch of Overlay.#batches) {
      for (const write of batch.writes) {
        if (write.type === type && write.id === id) {
          row = Overlay.#applyWrite(type, row, write);
        }
      }
    }

    return row;
  }

  static names(type, id) {
    const key = `${type} ${id}`;

    return Overlay.#batches.some((batch) => batch.rowKeys().has(key));
  }

  static push(batch) {
    Overlay.#batches.push(batch);
  }

  static remove(batch) {
    Overlay.#batches = Overlay.#batches.filter((held) => held !== batch);
  }

  // Deliberately NOT called by LocalDatabase.reset(): a resync replaces what the server said, and
  // what this client has written and not yet sent is not the server's to take away.
  static reset() {
    Overlay.#batches = [];
  }

  static #applyWrite(type, row, write) {
    switch (write.op) {
      case "create":
        return Overlay.#created(type, write);

      case "delete":
        return null;

      // A row the client no longer holds cannot be updated onto anything - the write still ships,
      // and the server answers for it against the row it has.
      case "update":
        return row === null ? null : Overlay.#updated(type, row, write);

      // An edge changes no column, so the row it names folds to the row it already was.
      default:
        return row;
    }
  }

  // The row a create will store, built from the write alone - the id it minted, the values it
  // carries, and both timestamps from its own stamp, which is the instant its writer made it.
  // Every settable field takes that stamp as its revision, which is what the server's insert does
  // with the same number.
  //
  // A base row already present means the frame confirming this create arrived before its answer
  // did. It is overwritten rather than merged, with values equal to its own.
  static #created(type, write) {
    const timestamp = Model.wireDateTime(Clock.wallClockMs(write.stamp));

    const revisions = Object.fromEntries(
      Model.settableFields(type).map((field) => [field, write.stamp]),
    );

    const row = Object.assign({id: write.id}, write.data, {
      created_at: timestamp,
      updated_at: timestamp,
      $revisions: revisions,
    });

    return Model.computeSortKeys(type, row);
  }

  // A moved counter takes no revision. There is nothing for a delta to be based on and nothing for
  // it to lose, which is what makes two clients' moves add up - its revision arrives with the
  // patch frame instead.
  static #updated(type, row, write) {
    const data = write.data ?? {};

    const updated = Object.assign({}, row, data, {
      updated_at: Model.wireDateTime(Clock.wallClockMs(write.stamp)),
    });

    updated["$revisions"] = Object.assign(
      {},
      row["$revisions"] ?? {},
      Object.fromEntries(
        Object.keys(data).map((field) => [field, write.stamp]),
      ),
    );

    for (const [counter, amount] of Object.entries(write.deltas ?? {})) {
      updated[counter] = row[counter] + amount;
    }

    return Model.computeSortKeys(type, updated);
  }
}

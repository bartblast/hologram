"use strict";

import Clock from "./clock.mjs";
import LocalDatabase from "./local_database.mjs";
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

    for (const write of Overlay.#writesFor(type, id)) {
      row = Overlay.#applyWrite(type, row, write);
    }

    return row;
  }

  // A type's whole table as the pending writes leave it - what a query reads. Nothing is cached:
  // the fold is rebuilt per call, deliberately.
  //
  // A cache here would have to be dropped whenever the base moves, whenever a batch is pushed or
  // dropped, AND whenever a write is appended to the batch that is still open - and it is that
  // last one that decides it. An action writes and then reads its own write on the next line, so a
  // cache that misses an append breaks read-your-writes, which is the promise this whole seam
  // exists to keep. Rebuilding costs a shallow copy of one table, and only while a write is
  // pending: with nothing pending the base is handed straight back, untouched and uncopied.
  static foldTable(type, base) {
    if (!Overlay.#namesType(type)) {
      return base;
    }

    const table = Object.assign({}, base);

    for (const batch of Overlay.#batches) {
      for (const write of batch.writes) {
        if (write.type === type) {
          Overlay.#fold(table, type, write);
        }
      }
    }

    return table;
  }

  // The target ids of one relationship of one row, as the pending edge writes leave them.
  static foldTargetIds(type, relationship, sourceId, base) {
    if (!Overlay.names(type, sourceId)) {
      return base;
    }

    let targetIds = new Set(base);

    for (const write of Overlay.#writesFor(type, sourceId)) {
      targetIds = Overlay.#applyEdge(targetIds, relationship, write);
    }

    return targetIds;
  }

  static names(type, id) {
    const key = `${type} ${id}`;

    return Overlay.#batches.some((batch) => batch.rowKeys().has(key));
  }

  // A confirmed batch's values ARE what the server stored, so they move out of the overlay and
  // into the base, and the layer goes with them. What a reader sees does not change - the folded
  // value and the promoted value are the same - which is why nothing flickers whichever arrives
  // first, this answer or the frame carrying the same rows.
  //
  // Applied against the BASE row rather than the folded one: a later batch may still be pending
  // over the same row, and its values are not the server's to store.
  //
  // A column the answer names as dropped is the one exception. Its value lost the merge, so the
  // base keeps what it has and the winner arrives with the frame.
  static promote(batch, dropped) {
    batch.writes.forEach((write, index) => {
      Overlay.#promoteWrite(write, dropped[String(index)] ?? {});
    });

    Overlay.remove(batch);
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

  static #applyEdge(targetIds, relationship, write) {
    // A row that is gone takes its outgoing edges with it, which is what the database itself does
    // when it drops one - the pairs it was the source of say nothing once there is no row.
    //
    // Judged unconditionally, where the ROW fold asks whether the delete still stands. The two
    // are not inconsistent: an edge fold is handed a set of target ids and never the row, so
    // there are no revisions here to weigh a delete against. A delete that turns out to have lost
    // costs an empty set until the answer arrives, where the row itself keeps standing - narrow,
    // and closing it means handing this the row, which no reader of a fact set has.
    if (write.op === "delete") {
      return new Set();
    }

    if (write.relationship !== relationship) {
      return targetIds;
    }

    if (write.op === "add_relationship") {
      targetIds.add(write.target_id);
    } else if (write.op === "delete_relationship") {
      targetIds.delete(write.target_id);
    }

    return targetIds;
  }

  static #applyWrite(type, row, write) {
    switch (write.op) {
      case "create":
        return Overlay.#created(type, write);

      // A delete takes the row only when nothing has moved past the stamp it was made at, which
      // is the server's own rule for one. A newer edit from elsewhere means the server is going
      // to keep the row - so it keeps standing here too, rather than being gone until an answer
      // says it never went.
      case "delete":
        return Overlay.#deleteWins(row, write) ? null : row;

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

  // Whether a delete still stands against the base - the mirror of the server's rule for one,
  // which takes the row only when the write wins against EVERY revision it holds. One column
  // moved past the stamp is enough to keep the whole row, because a delete is a claim about all
  // of them at once.
  //
  // A row holding no revisions has nothing that could have moved, and a row that is already gone
  // has nothing to keep - both answer that the delete stands.
  static #deleteWins(row, write) {
    return (
      row === null ||
      Object.keys(row["$revisions"] ?? {}).every((field) =>
        Overlay.#wins(row, write, field),
      )
    );
  }

  static #fold(table, type, write) {
    const folded = Overlay.#applyWrite(type, table[write.id] ?? null, write);

    if (folded === null) {
      delete table[write.id];
    } else {
      table[write.id] = folded;
    }
  }

  static #namesType(type) {
    return Overlay.#batches.some((batch) =>
      batch.writes.some((write) => write.type === type),
    );
  }

  static #promoteWrite(write, droppedColumns) {
    if (write.op === "add_relationship") {
      LocalDatabase.addFact(
        write.type,
        write.relationship,
        write.id,
        write.target_id,
      );

      return;
    }

    if (write.op === "delete_relationship") {
      LocalDatabase.deleteFact(
        write.type,
        write.relationship,
        write.id,
        write.target_id,
      );

      return;
    }

    const base = LocalDatabase.baseRow(write.type, write.id);
    const promoted = Overlay.#applyWrite(write.type, base, write);

    if (promoted === null) {
      LocalDatabase.deleteRow(write.type, write.id);

      return;
    }

    for (const name of Object.keys(droppedColumns)) {
      Overlay.#restoreColumn(promoted, base, name);
    }

    LocalDatabase.putRow(
      write.type,
      Model.computeSortKeys(write.type, promoted),
    );
  }

  // A column whose value lost keeps what the base holds - its value AND its revision, since the
  // revision this write would have set is not the one the row now carries.
  static #restoreColumn(promoted, base, name) {
    const revisions = base?.["$revisions"] ?? {};

    promoted[name] = base === null ? null : base[name];

    if (name in revisions) {
      promoted["$revisions"][name] = revisions[name];
    } else {
      delete promoted["$revisions"][name];
    }
  }

  // A moved counter takes no revision. There is nothing for a delta to be based on and nothing for
  // it to lose, which is what makes two clients' moves add up - its revision arrives with the
  // patch frame instead. A move is therefore applied whatever the base holds, exactly as the
  // server applies it: what keeps a move that has ALREADY landed from being added a second time
  // is the batch's landed set, never a revision, since the server does not store a mover's stamp
  // when it advances a contended counter.
  //
  // A VALUE column is the opposite, and is applied only where it still wins against what the base
  // now holds. That is the server's own merge rule read locally, so what shows is the answer the
  // server is going to give rather than a guess at it: a newer value from elsewhere appears the
  // moment its frame lands, instead of sitting under a pending write until the round trip ends.
  //
  // Nothing applies, nothing is built - the base row is handed back UNCOPIED, which keeps a write
  // whose columns have all been overtaken from costing a copy of the row on every read.
  static #updated(type, row, write) {
    const data = write.data ?? {};
    const deltas = Object.entries(write.deltas ?? {});

    const applied = Object.keys(data).filter((field) =>
      Overlay.#wins(row, write, field),
    );

    if (applied.length === 0 && deltas.length === 0) {
      return row;
    }

    const updated = Object.assign({}, row, {
      updated_at: Model.wireDateTime(Clock.wallClockMs(write.stamp)),
    });

    // Copied rather than shared: writing a revision into it otherwise reaches into the base's own
    // map, which every other reader of that row is holding.
    updated["$revisions"] = Object.assign({}, row["$revisions"] ?? {});

    for (const field of applied) {
      updated[field] = data[field];
      updated["$revisions"][field] = write.stamp;
    }

    for (const [counter, amount] of deltas) {
      updated[counter] = row[counter] + amount;
    }

    return Model.computeSortKeys(type, updated);
  }

  // Whether a write's value for one column still stands against the base, which is what the
  // server's merge asks of it: the stamp has to be above the revision the column now holds.
  //
  // The server's other half - "the writer saw the revision that is stored" - is implied here
  // rather than checked. A client stamps above every revision it has observed, and based_on is
  // what it observed, so a column that has not moved passes the stamp comparison by construction.
  //
  // A column the base holds no revision for reads as revision zero: never set by anyone, so
  // nothing can have moved past it. The same reading the server makes.
  static #wins(row, write, field) {
    return write.stamp > (row["$revisions"]?.[field] ?? 0);
  }

  // Every pending write naming one row, in the order they were made.
  static #writesFor(type, id) {
    return Overlay.#batches.flatMap((batch) =>
      batch.writes.filter((write) => write.type === type && write.id === id),
    );
  }
}

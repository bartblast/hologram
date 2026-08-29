"use strict";

import Clock from "./clock.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";

// What a frame does to the database. Deltas arrive grouped by op and then by entity type, and
// each of them is a statement about one moment - so they may be applied in any order. A row and
// an edge of its own do both arrive in one frame, and agree rather than conflict: the row states
// the whole target set of a relationship, the edge states one pair of it, and the server read
// both from one round. A patch cannot enter into it at all, since it merges into the FILED row,
// whose relationships were split into the facts when it was filed.
//
// Rows arrive flat and are filed flat. A row carries the target ids of the relationships the
// query included, never the rows behind them - those travel as deltas of their own - so filing
// one means putting its attributes in its type's table and its target ids in the relationship
// facts, with nothing left nested.
export default class Deltas {
  // `insertOnly` is how rows a page carried are applied, which changes two things and nothing
  // else: a row already held is left alone, and one that is filed is remembered as unconfirmed
  // until the stream delivers it.
  //
  // Left alone because what a page carries can be OLDER than what the client holds - a page
  // rendered at one moment lands after the stream delivered a later change to the same row - and
  // overwriting would put back a value nothing will correct, since the server sees nothing new to
  // send. It loses nothing: every change to a row the client already has arrives on the stream,
  // in order.
  static apply(deltas, opts = {}) {
    for (const [op, byType] of Object.entries(deltas)) {
      for (const [type, items] of Object.entries(byType)) {
        for (const item of items) {
          Deltas.#applyOne(op, type, item, opts);
        }
      }
    }
  }

  static #applyOne(op, type, item, opts) {
    switch (op) {
      case "add_relationship":
        LocalDatabase.addFact(type, item.relationship, item.id, item.target_id);
        break;

      case "del_relationship":
        LocalDatabase.deleteFact(
          type,
          item.relationship,
          item.id,
          item.target_id,
        );
        break;

      // A row gone and a row out of reach are told apart nowhere on this side: both mean the
      // client no longer holds it. The server sends only the second - the first is what offline
      // writes will need the difference for.
      case "del_entity":
      case "unsync_entity":
        LocalDatabase.deleteRow(type, item);
        break;

      case "patch_entity":
        Deltas.#patchRow(type, item);
        break;

      case "put_entity":
        Deltas.#putRow(type, item, opts);
        break;

      default:
        throw new HologramRuntimeError(`unknown sync delta op: ${op}`);
    }
  }

  // A patch names a row the client was told about, so one naming a row it does not hold is one
  // it has already been told to let go of - a resync between the two is enough for that to
  // happen. Filing the changes alone would leave a row with holes where its other attributes
  // should be, and nothing would ever fill them.
  static #patchRow(type, changes) {
    Deltas.#observeRevisions(changes);

    const held = LocalDatabase.baseRow(type, changes.id);

    if (held === null) {
      return;
    }

    const merged = Object.assign({}, held, changes);

    // A patch carries the revisions of the columns it names and nothing else, so the row's map is
    // the held one with those written over it - the assign above would otherwise have replaced the
    // whole map with the partial one, losing the revision of every column the patch left alone.
    merged["$revisions"] = Object.assign(
      {},
      held["$revisions"] ?? {},
      changes["$revisions"] ?? {},
    );

    Deltas.#fileRow(type, merged);
  }

  static #putRow(type, row, opts) {
    Deltas.#observeRevisions(row);

    if (opts.insertOnly) {
      if (LocalDatabase.baseRow(type, row.id) !== null) {
        return;
      }

      Deltas.#fileRow(type, row);
      LocalDatabase.markCarried(type, row.id);

      return;
    }

    Deltas.#fileRow(type, row);

    // The stream has delivered it, so it is no longer a row the client only has because a page
    // carried it - and no longer one the completeness marker should take away.
    LocalDatabase.unmarkCarried(type, row.id);
  }

  static #fileRow(type, row) {
    const relationships = Model.relationships(type);
    const attributes = {};
    const facts = [];

    for (const [key, value] of Object.entries(row)) {
      if (relationships[key]?.toMany) {
        facts.push([key, value]);
      } else {
        attributes[key] = value;
      }
    }

    Model.computeSortKeys(type, attributes);
    LocalDatabase.putRow(type, attributes);

    // The whole target set of the relationship as it now stands, which is what a row states
    // about one: pairs it no longer names are pairs it no longer has.
    for (const [name, targetIds] of facts) {
      LocalDatabase.replaceFacts(type, name, row.id, targetIds);
    }
  }

  // The clock's receive rule: every revision that ARRIVES lifts the clock past it, so a stamp this
  // client authors is above everything the server has told it about - which is what lets a write's
  // based_on be read as "the revision I saw" rather than as a guess.
  //
  // Deliberately about arrival rather than about what is kept, so it runs before a patch for an
  // unheld row is passed over and before a carried row already held is left alone. Neither of
  // those can reach a based_on today (both concern rows this client either lacks or holds a
  // filed copy of), so the conservative reading costs nothing and needs no case analysis.
  static #observeRevisions(row) {
    for (const revision of Object.values(row["$revisions"] ?? {})) {
      Clock.observe(revision);
    }
  }
}

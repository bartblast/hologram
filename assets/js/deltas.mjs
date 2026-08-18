"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";
import SortKey from "./sort_key.mjs";

// What a frame does to the database. Deltas arrive grouped by op and then by entity type, and
// each of them is a statement about one moment: no row is spoken of twice in a frame, so they
// may be applied in any order.
//
// Rows arrive flat and are filed flat. A row carries the target ids of the relationships the
// query included, never the rows behind them - those travel as deltas of their own - so filing
// one means putting its attributes in its type's table and its target ids in the relationship
// facts, with nothing left nested.
export default class Deltas {
  static apply(deltas) {
    for (const [op, byType] of Object.entries(deltas)) {
      for (const [type, items] of Object.entries(byType)) {
        for (const item of items) {
          Deltas.#applyOne(op, type, item);
        }
      }
    }
  }

  static #applyOne(op, type, item) {
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
        Deltas.#putRow(type, item);
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
    const held = LocalDatabase.getRow(type, changes.id);

    if (held === null) {
      return;
    }

    Deltas.#fileRow(type, Object.assign({}, held, changes));
  }

  static #putRow(type, row) {
    Deltas.#fileRow(type, row);
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

    Deltas.#computeSortKeys(type, attributes);
    LocalDatabase.putRow(type, attributes);

    // The whole target set of the relationship as it now stands, which is what a row states
    // about one: pairs it no longer names are pairs it no longer has.
    for (const [name, targetIds] of facts) {
      LocalDatabase.replaceFacts(type, name, row.id, targetIds);
    }
  }

  // Which attributes need a key is compile-time true - the build bakes the pairs its own queries
  // order by - and the key itself is derived, so it is computed here rather than sent.
  static #computeSortKeys(type, attributes) {
    for (const [pairType, name] of globalThis.Hologram.sync
      ?.orderedStringPairs ?? []) {
      if (pairType === type) {
        const value = attributes[name];

        attributes[`${name}_sort`] =
          value === null || value === undefined ? null : SortKey.compute(value);
      }
    }
  }
}

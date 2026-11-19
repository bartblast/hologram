"use strict";

import Clock from "./clock.mjs";
import DropHash from "./drop_hash.mjs";
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
  // The hashes of the held ids of each type under the salt of the catch-up telling them, worked out
  // at the catch-up's first hashed drop of the type rather than once per frame - every frame of one
  // catch-up hashes under one salt. A row filed after they were worked out is passed over, which is
  // right: the server hashes only rows it doesn't take the client to hold, and every row a catch-up
  // hands over is one it then takes the client to hold, and drops by id - bar a row a page carries,
  // which joins them (see `#putRow`). Kept until the next
  // catch-up's salt replaces them: a hash per held row of the types a catch-up dropped any of.
  static #hashes = {byType: new Map(), salt: null};

  // Forgets the hashes worked out for the last catch-up.
  static reset() {
    Deltas.#hashes = {byType: new Map(), salt: null};
  }

  // `insertOnly` is how rows a page carried are applied, which changes two things and nothing
  // else: a row already held is left alone, and one that is filed is remembered as unconfirmed
  // until the stream delivers it.
  //
  // Left alone because what a page carries can be OLDER than what the client holds - a page
  // rendered at one moment lands after the stream delivered a later change to the same row - and
  // overwriting would put back a value nothing will correct, since the server sees nothing new to
  // send. It loses nothing: every change to a row the client already has arrives on the stream,
  // in order.
  //
  // Answers the rows this frame WROTE, each keyed "<type> <id>" - what a pending write of this
  // client's is matched against to learn that the base now holds its effect.
  //
  // Written, not merely mentioned. A delta the ingest passes over - a patch for a row the client
  // does not hold, a carried row it already has - leaves the base exactly as it was, so nothing
  // about it can be said to be in there. Naming it anyway would take a pending CREATE off the
  // screen: the fold would skip a write whose row the base does not carry, and nothing would put
  // it back until the answer arrived.
  static apply(deltas, opts = {}) {
    const written = new Set();

    for (const [op, byType] of Object.entries(deltas)) {
      for (const [type, items] of Object.entries(byType)) {
        if (op === "unsync_hashed") {
          for (const key of Deltas.#dropHashed(type, items)) {
            written.add(key);
          }

          continue;
        }

        for (const item of items) {
          const id = Deltas.#applyOne(op, type, item, opts);

          if (id !== null) {
            written.add(`${type} ${id}`);
          }
        }
      }
    }

    return written;
  }

  // Answers the id of the row it wrote, or null when it wrote none.
  static #applyOne(op, type, item, opts) {
    switch (op) {
      // An edge names its SOURCE row, which is the row whose relationships changed - the same row
      // a batch's edge write names.
      case "add_relationship":
        LocalDatabase.addFact(type, item.relationship, item.id, item.target_id);

        return item.id;

      case "del_relationship":
        LocalDatabase.deleteFact(
          type,
          item.relationship,
          item.id,
          item.target_id,
        );

        return item.id;

      // A row gone and a row out of reach are told apart nowhere on this side: both mean the
      // client no longer holds it. The server sends only the second - the first is what offline
      // writes will need the difference for.
      case "del_entity":
      case "unsync_entity":
        LocalDatabase.deleteRow(type, item);

        return item;

      case "patch_entity":
        return Deltas.#patchRow(type, item);

      case "put_entity":
        return Deltas.#putRow(type, item, opts);

      default:
        throw new HologramRuntimeError(`unknown sync delta op: ${op}`);
    }
  }

  // The server tells a client to drop a row by hash when it can't say whether the client holds it:
  // telling it the id would tell it that a row it may not read exists. So the client drops the rows
  // it holds whose ids hash to one it was sent, and knows nothing more of the rest.
  //
  // A row it drops this way can be named by the sets of rows it still holds, and the server, not
  // knowing it was held, tells nothing of those pairs - so they go too, or a set would name a row
  // the client was never told is back. Answers the key of every row it dropped and of every row the
  // stream vouched for whose set it took one out of, both of which it wrote and storing keeps. The
  // server sends these in frames claiming no number of the client's own batches, so naming a row
  // whose set changed lands no pending write on it.
  static #dropHashed(type, items) {
    const dropped = new Set();

    for (const {hashes, salt} of items) {
      const held = Deltas.#hashedIds(type, salt);

      for (const hash of hashes) {
        const id = held.get(hash);

        if (id !== undefined && LocalDatabase.baseRow(type, id) !== null) {
          dropped.add(id);
        }
      }
    }

    if (dropped.size === 0) {
      return [];
    }

    for (const id of dropped) {
      LocalDatabase.deleteRow(type, id);
    }

    const written = Array.from(dropped, (id) => `${type} ${id}`);

    return written.concat(Deltas.#deleteFactsNaming(type, dropped));
  }

  // Every pair filed under a held row that names one of the given rows of the given type: in a
  // to-many of that type, and in an inverse of a to-many whose source is of that type.
  static #deleteFactsNaming(type, ids) {
    const written = [];

    // A row a page carried is never stored, so one whose set changed isn't written either.
    const carried = new Set(
      LocalDatabase.carriedEntries().map(
        ([carriedType, id]) => `${carriedType} ${id}`,
      ),
    );

    for (const holderType of Object.keys(
      globalThis.Hologram.sync?.model ?? {},
    )) {
      const relationships = Object.entries(
        Model.relationships(holderType) ?? {},
      )
        .filter(
          ([_name, relationship]) =>
            relationship.toMany && relationship.type === type,
        )
        .map(([name]) => name);

      const inverses = Object.entries(Model.inverses(holderType) ?? {})
        .filter(
          ([_name, inverse]) => !inverse.reference && inverse.type === type,
        )
        .map(([name]) => name);

      const names = relationships.concat(inverses);

      if (names.length === 0) {
        continue;
      }

      for (const holderId of Object.keys(LocalDatabase.baseTable(holderType))) {
        let changed = false;

        // Read through the set rather than through the dropped ids, which can be many more than
        // a set holds.
        for (const name of names) {
          const named = Array.from(
            LocalDatabase.baseTargetIds(holderType, name, holderId),
          ).filter((targetId) => ids.has(targetId));

          for (const targetId of named) {
            LocalDatabase.deleteFact(holderType, name, holderId, targetId);
            changed = true;
          }
        }

        const key = `${holderType} ${holderId}`;

        if (changed && !carried.has(key)) {
          written.push(key);
        }
      }
    }

    return written;
  }

  static #hashedIds(type, salt) {
    if (Deltas.#hashes.salt !== salt) {
      Deltas.#hashes = {byType: new Map(), salt};
    }

    let byHash = Deltas.#hashes.byType.get(type);

    if (byHash === undefined) {
      byHash = new Map();

      for (const id of Object.keys(LocalDatabase.baseTable(type))) {
        byHash.set(DropHash.hash(salt, id), id);
      }

      Deltas.#hashes.byType.set(type, byHash);
    }

    return byHash;
  }

  // A patch names a row the client was told about, so one naming a row it does not hold is one
  // it has already been told to let go of - a resync between the two is enough for that to
  // happen. Filing the changes alone would leave a row with holes where its other attributes
  // should be, and nothing would ever fill them.
  static #patchRow(type, changes) {
    Deltas.#observeRevisions(changes);

    const held = LocalDatabase.baseRow(type, changes.id);

    if (held === null) {
      return null;
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

    return changes.id;
  }

  static #putRow(type, row, opts) {
    Deltas.#observeRevisions(row);

    if (opts.insertOnly) {
      if (LocalDatabase.baseRow(type, row.id) !== null) {
        return null;
      }

      Deltas.#fileRow(type, row);
      LocalDatabase.markCarried(type, row.id);

      // A page can land in the middle of a catch-up, with a row its user lost since the page was
      // rendered - one the server doesn't take the client to hold, and hashes. So a row a page
      // carries joins the hashes already worked out for its type.
      Deltas.#hashes.byType
        .get(type)
        ?.set(DropHash.hash(Deltas.#hashes.salt, row.id), row.id);

      return row.id;
    }

    Deltas.#fileRow(type, row);

    // The stream has delivered it, so it is no longer a row the client only has because a page
    // carried it - and no longer one the completeness marker should take away.
    LocalDatabase.unmarkCarried(type, row.id);

    return row.id;
  }

  // A to-many's ids and an inverse of a to-many's ids are facts - the second read off the related
  // rows' edges by the server, and kept current by the edges it reports for them.
  static #fileRow(type, row) {
    const relationships = Model.relationships(type);
    const inverses = Model.inverses(type);
    const attributes = {};
    const facts = [];

    for (const [key, value] of Object.entries(row)) {
      const factKey =
        (Object.hasOwn(relationships, key) && relationships[key].toMany) ||
        (Object.hasOwn(inverses, key) && !inverses[key].reference);

      if (factKey) {
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

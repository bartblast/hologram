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
  // The hashes of the ids of each type the client holds a row of or finds in a set, under the salt
  // of the catch-up telling them, each id hashed once per catch-up rather than once per frame -
  // every frame of one catch-up hashes under one salt. A row filed since the last hashed drop of
  // its type - one a page carried, or one the client's own write filed when its answer came - is
  // hashed when the next one arrives. Kept until the next catch-up's salt replaces them or `reset`
  // forgets them: a hash per such id of the types a catch-up dropped any of by hash, less the ones
  // a hashed drop took.
  static #hashes = {byType: new Map(), salt: null};

  // Forgets the hashes worked out for the last catch-up.
  static reset() {
    Deltas.#hashes = {byType: new Map(), salt: null};
  }

  // `insertOnly` is how rows a page carried are applied, which changes three things and nothing
  // else: a row already held is left alone, one that is filed is remembered as unconfirmed until
  // the stream delivers it, and its numbers past the final point are kept beside the row as shown
  // rather than in it (see LocalDatabase.carryNumbers), held row or not.
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
    LocalDatabase.takeStoredFactRemovals();

    const written = new Set();

    for (const [op, byType] of Object.entries(deltas)) {
      for (const [type, items] of Object.entries(byType)) {
        if (op === "unsync_hashed" || op === "keep_hashed") {
          const keys =
            op === "unsync_hashed"
              ? Deltas.#dropHashed(type, items)
              : Deltas.#keepHashed(type, items);

          for (const key of keys) {
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
  // the client was never told is back. So does a pair naming a row the client doesn't hold: a stream
  // cut inside a batch or a catch-up can leave one, and this is the only word that reaches it. Such
  // an id is one the client already has, so hashing it learns nothing. Answers the key of every row
  // it dropped and of every row the stream vouched for whose set it took one out of, both of which
  // it wrote and storing keeps. The server sends these in frames claiming no number of the client's
  // own batches, so naming a row whose set changed lands no pending write on it.
  static #dropHashed(type, items) {
    const dropped = new Set();

    for (const {hashes, salt} of items) {
      const hashed = Deltas.#hashedIds(type, salt);

      for (const hash of hashes) {
        const id = hashed.byHash.get(hash);

        // Forgotten once dropped, so a hash told again finds nothing and walks no pairs. Filed
        // again, the id is hashed again.
        if (id !== undefined) {
          dropped.add(id);
          hashed.byHash.delete(hash);
          hashed.ids.delete(id);
        }
      }
    }

    return Deltas.#dropRows(type, dropped);
  }

  // The server tells a client which rows of a type it may keep, by hash, when its user lost a grant
  // reaching every row of the type: the rows the grant hid can't be named, the rows still readable
  // can. So every held row of the type whose id hashes to none of them goes, as a hashed drop takes
  // a row, and so does every pair naming an id off the list that the client holds no row of. Hashed
  // here rather than looked up in the catch-up's hashes, which can miss rows filed since they were
  // worked out - and every one of those has to be judged against the list.
  static #keepHashed(type, items) {
    const dropped = new Set();

    for (const {hashes, salt} of items) {
      const kept = new Set(hashes);

      for (const id of LocalDatabase.heldOrNamedIds(type)) {
        if (!kept.has(DropHash.hash(salt, id))) {
          dropped.add(id);
        }
      }
    }

    return Deltas.#dropRows(type, dropped);
  }

  // An id the client holds no row of is only taken out of the sets naming it, here and in storage.
  // It isn't a row this frame wrote, and neither are the rows whose sets named it.
  static #dropRows(type, ids) {
    if (ids.size === 0) {
      return [];
    }

    const held = new Set();
    const unheld = new Set();

    for (const id of ids) {
      (LocalDatabase.baseRow(type, id) === null ? unheld : held).add(id);
    }

    const written = [];

    for (const id of held) {
      LocalDatabase.deleteRow(type, id);
      written.push(`${type} ${id}`);
    }

    return written
      .concat(LocalDatabase.deleteFactsNaming(type, held))
      .concat(
        LocalDatabase.deleteFactsNaming(type, unheld, {writeHolders: false}),
      );
  }

  static #hashedIds(type, salt) {
    if (Deltas.#hashes.salt !== salt) {
      Deltas.#hashes = {byType: new Map(), salt};
    }

    let hashed = Deltas.#hashes.byType.get(type);

    if (hashed === undefined) {
      hashed = {byHash: new Map(), ids: new Set(), readAt: null};
      Deltas.#hashes.byType.set(type, hashed);
    }

    // Reading every id walks every pair the client holds, and a big drop arrives over many frames
    // in a row, so it's read again only when something was filed since, or new rules gave the model
    // a set that can name the type.
    const readAt = `${LocalDatabase.filings()} ${Model.generation()}`;

    if (hashed.readAt === readAt) {
      return hashed;
    }

    hashed.readAt = readAt;

    for (const id of LocalDatabase.heldOrNamedIds(type)) {
      if (!hashed.ids.has(id)) {
        hashed.byHash.set(DropHash.hash(salt, id), id);
        hashed.ids.add(id);
      }
    }

    return hashed;
  }

  // A patch names a row the client was told about, so one naming a row it does not hold is one
  // it has already been told to let go of - a resync between the two is enough for that to
  // happen. Filing the changes alone would leave a row with holes where its other attributes
  // should be, and nothing would ever fill them.
  //
  // An updated number above the final point waits beside the row, which keeps the one it held.
  static #patchRow(type, changes) {
    Deltas.#observeRevisions(changes);

    const held = LocalDatabase.baseRow(type, changes.id);

    if (held === null) {
      return null;
    }

    const merged = Object.assign(
      {},
      held,
      LocalDatabase.holdNumbers(type, changes),
    );

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

  // A row holds only the numbers that are final here, the rest waiting beside it (see
  // LocalDatabase.holdNumbers) - or, for one a page carried, kept beside it as shown (see
  // LocalDatabase.carryNumbers), since the render left out every number the server could not call
  // final.
  static #putRow(type, row, opts) {
    Deltas.#observeRevisions(row);

    if (opts.insertOnly) {
      // A number the page showed is kept even for a row held already, since a list orders the row
      // by it until the stream's own is final.
      const carried = LocalDatabase.carryNumbers(type, row);

      if (LocalDatabase.baseRow(type, row.id) !== null) {
        return null;
      }

      Deltas.#fileRow(type, carried);
      LocalDatabase.markCarried(type, row.id);

      return row.id;
    }

    Deltas.#fileRow(type, LocalDatabase.holdNumbers(type, row));

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

    Model.computeSortKeys(type, Model.readIntegers(type, attributes));
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

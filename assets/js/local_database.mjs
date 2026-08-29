"use strict";

// The client's entity database: one plain table per entity type plus to-many relationship
// facts, holding rows exactly as the wire spells them - plain JSON values, sort keys beside
// them. Boxed terms are built only at the query result boundary, never stored here.
//
// The pot is flat. An entity reached through another entity's include lives in its own table
// like any other, and a to-many relationship is a fact pairing two ids - assembling includes is
// the reader's job, at read time. What the database holds is decided by the server, row by row:
// there is no client-side eviction, a row leaves when the server says it is no longer this
// client's to hold.

import Model from "./model.mjs";
import Overlay from "./overlay.mjs";

// What joins a type and an id into one carried-mark key. A NUL cannot occur in either half, so
// the two can never be told apart wrongly - and it is spelled as an escape rather than written
// into the file as a raw byte, which is what used to make git call this source binary and every
// grep over it come back empty.
const SEPARATOR = "\u0000";

export default class LocalDatabase {
  // Who the client is, for the predicates that name the acting user - nil for a visitor. It
  // arrives with the page rather than with the rows, and a resync does not clear it: what the
  // client may see can change without anyone becoming someone else.
  static actorUserId = null;

  // What the render that handed this page over counted, keyed by the prop instance that asked -
  // held until this client's own database is complete enough to count for itself.
  static syncCounts = {};

  // type -> relationship -> source id -> Set of target ids
  static #facts = {};

  // The rows that arrived with the page rather than from the stream, until the stream confirms
  // them. What is still here when the fill declares itself complete was never the client's to
  // hold - a grant revoked between the render and the connect leaves exactly that.
  static #carried = new Set();

  // The scopes the server has declared complete ("page", "all") - until a scope arrives, the
  // database answers with part of the truth and its readers must not treat it as the whole.
  static #syncedScopes = new Set();

  // type -> id -> row
  static #tables = {};

  static addFact(type, relationship, sourceId, targetId) {
    LocalDatabase.#targetIds(type, relationship, sourceId).add(targetId);
  }

  // The three below answer what the SERVER last said, with no pending write folded in. Ingest
  // asks these: a frame is a statement about the server's row, so deciding whether the client
  // holds one has to be asked of the server's copy - a row that exists only as a write this
  // client has not sent yet is not a row the server can be talking about.
  static baseRow(type, id) {
    return LocalDatabase.#tables[type]?.[id] ?? null;
  }

  static baseTable(type) {
    return LocalDatabase.#tables[type] ?? {};
  }

  static baseTargetIds(type, relationship, sourceId) {
    return LocalDatabase.#facts[type]?.[relationship]?.[sourceId] ?? new Set();
  }

  static deleteFact(type, relationship, sourceId, targetId) {
    LocalDatabase.#facts[type]?.[relationship]?.[sourceId]?.delete(targetId);
  }

  // A row leaving takes its relationship facts with it - the pairs it was the source of say
  // nothing once there is no row to read them from.
  static deleteRow(type, id) {
    const table = LocalDatabase.#tables[type];

    if (table) {
      delete table[id];
    }

    const typeFacts = LocalDatabase.#facts[type];

    if (typeFacts) {
      for (const relationship of Object.keys(typeFacts)) {
        delete typeFacts[relationship][id];
      }
    }
  }

  // Every READ passes through the overlay, so what a query, a policy check or an action sees is
  // the row as this client last left it - its own unsent writes folded over what the server sent.
  // With nothing pending each of these hands back exactly what the base one does, same object
  // included.
  static getRow(type, id) {
    return Overlay.foldRow(type, id, LocalDatabase.baseRow(type, id));
  }

  static getTable(type) {
    return Overlay.foldTable(type, LocalDatabase.baseTable(type));
  }

  static getTargetIds(type, relationship, sourceId) {
    return Overlay.foldTargetIds(
      type,
      relationship,
      sourceId,
      LocalDatabase.baseTargetIds(type, relationship, sourceId),
    );
  }

  static isSynced(scope) {
    return LocalDatabase.#syncedScopes.has(scope);
  }

  static carriedEntries() {
    return Array.from(LocalDatabase.#carried, (entry) =>
      entry.split(SEPARATOR),
    );
  }

  static markCarried(type, id) {
    LocalDatabase.#carried.add(`${type}${SEPARATOR}${id}`);
  }

  static unmarkCarried(type, id) {
    LocalDatabase.#carried.delete(`${type}${SEPARATOR}${id}`);
  }

  // The whole-pot marker is what makes a carried row's absence mean something: the fill is
  // complete at "all" by definition, so a row still held only because a page carried it is one
  // the server never sent - a grant revoked between that render and this connect leaves exactly
  // that. Dropped here rather than left to be read, which is the discard the resync path makes.
  static markSynced(scope) {
    LocalDatabase.#syncedScopes.add(scope);

    if (scope === "all") {
      LocalDatabase.#sweepCarried();
    }
  }

  static putRow(type, row) {
    let table = LocalDatabase.#tables[type];

    if (!table) {
      table = {};
      LocalDatabase.#tables[type] = table;
    }

    table[row.id] = row;
  }

  // What one frame's rows look like on their way to durable storage: a record per row, holding the
  // row exactly as the base holds it - plain values, sort keys, $revisions - with the target ids of
  // its to-many relationships beside it.
  //
  // The facts ride WITH their source row rather than in a place of their own, because that is how
  // they are keyed here: a row leaving takes them with it, and an edge names the row whose
  // relationships changed. So one row is one record, and one change is one write. A to-one is not
  // among them - it lives in the row itself, as a reference field.
  //
  // A key the base no longer holds answers a record with no row, which is what a frame that
  // deleted or unsynced one leaves behind. Deciding what to do about that is the reader's.
  static records(rowKeys) {
    return Array.from(rowKeys, (rowKey) => {
      const separator = rowKey.indexOf(" ");
      const type = rowKey.slice(0, separator);
      const id = rowKey.slice(separator + 1);
      const row = LocalDatabase.baseRow(type, id);

      return row === null
        ? {id, row: null, type}
        : {facts: LocalDatabase.#toManyFacts(type, id), id, row, type};
    });
  }

  // The whole current target set for one (source, relationship) - the snapshot statement a row's
  // id list carries, replacing whatever pairs were held before.
  static replaceFacts(type, relationship, sourceId, targetIds) {
    const targets = LocalDatabase.#targetIds(type, relationship, sourceId);

    targets.clear();

    for (const targetId of targetIds) {
      targets.add(targetId);
    }
  }

  // The overlay is deliberately NOT reset here. This runs on a resync, which replaces what the
  // SERVER said - and what this client has written and not yet sent is not the server's to take
  // away. Overlay.reset() exists for the callers that do mean it.
  static reset() {
    LocalDatabase.syncCounts = {};
    LocalDatabase.#carried = new Set();
    LocalDatabase.#facts = {};
    LocalDatabase.#syncedScopes = new Set();
    LocalDatabase.#tables = {};
  }

  static #sweepCarried() {
    for (const [type, id] of LocalDatabase.carriedEntries()) {
      LocalDatabase.deleteRow(type, id);
    }

    LocalDatabase.#carried = new Set();
  }

  static #toManyFacts(type, id) {
    const facts = {};

    for (const [name, relationship] of Object.entries(
      Model.relationships(type),
    )) {
      if (relationship.toMany) {
        facts[name] = Array.from(LocalDatabase.baseTargetIds(type, name, id));
      }
    }

    return facts;
  }

  static #targetIds(type, relationship, sourceId) {
    let typeFacts = LocalDatabase.#facts[type];

    if (!typeFacts) {
      typeFacts = {};
      LocalDatabase.#facts[type] = typeFacts;
    }

    let relationshipFacts = typeFacts[relationship];

    if (!relationshipFacts) {
      relationshipFacts = {};
      typeFacts[relationship] = relationshipFacts;
    }

    let targets = relationshipFacts[sourceId];

    if (!targets) {
      targets = new Set();
      relationshipFacts[sourceId] = targets;
    }

    return targets;
  }
}

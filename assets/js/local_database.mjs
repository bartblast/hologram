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

export default class LocalDatabase {
  // type -> relationship -> source id -> Set of target ids
  static #facts = {};

  // The scopes the server has declared complete ("page", "all") - until a scope arrives, the
  // database answers with part of the truth and its readers must not treat it as the whole.
  static #syncedScopes = new Set();

  // type -> id -> row
  static #tables = {};

  static addFact(type, relationship, sourceId, targetId) {
    LocalDatabase.#targetIds(type, relationship, sourceId).add(targetId);
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

  static getRow(type, id) {
    return LocalDatabase.#tables[type]?.[id] ?? null;
  }

  static getTable(type) {
    return LocalDatabase.#tables[type] ?? {};
  }

  static getTargetIds(type, relationship, sourceId) {
    return LocalDatabase.#facts[type]?.[relationship]?.[sourceId] ?? new Set();
  }

  static isSynced(scope) {
    return LocalDatabase.#syncedScopes.has(scope);
  }

  static markSynced(scope) {
    LocalDatabase.#syncedScopes.add(scope);
  }

  static putRow(type, row) {
    let table = LocalDatabase.#tables[type];

    if (!table) {
      table = {};
      LocalDatabase.#tables[type] = table;
    }

    table[row.id] = row;
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

  static reset() {
    LocalDatabase.#facts = {};
    LocalDatabase.#syncedScopes = new Set();
    LocalDatabase.#tables = {};
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

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

import IdentityTracker from "./identity_tracker.mjs";
import Model from "./model.mjs";
import Overlay from "./overlay.mjs";

// What joins a type and an id into one carried-mark key. A NUL cannot occur in either half, so
// the two can never be told apart wrongly - and it is spelled as an escape rather than written
// into the file as a raw byte, which is what used to make git call this source binary and every
// grep over it come back empty.
const SEPARATOR = "\u0000";

// How many carried counts are kept. They last until the client can count for itself, so a tab that
// visits pages and never hears a marker would otherwise keep one for every query it was handed.
const CARRIED_COUNTS_LIMIT = 1000;

// How much text their keys may add up to, since a key spells a whole query and every value in it.
const CARRIED_COUNT_KEYS_LENGTH_LIMIT = 4_000_000;

// How much of that text one page snapshot may save, since a snapshot that doesn't fit in session
// storage on unload is lost whole.
const SAVED_COUNT_KEYS_LENGTH_LIMIT = 256_000;

export default class LocalDatabase {
  // Who the client is, the session's user id as exact text from the server - null for a visitor.
  // It only tells owners apart: it names whose rows and queued writes this database holds, and is
  // never an id to look up. It arrives with the page rather than with the rows, and a resync does
  // not clear it: what the client may see can change without anyone becoming someone else.
  static actorUserId = null;

  // The same user as the data layer reads them - the id of a user entity, or null for a visitor and
  // for a user id no user entity can have, like an app's own serial id. The rules, the grants and
  // the session user ask about this one, the way the server's data layer does; who owns the rows
  // and the queued writes is the id above, which keeps two such users of one browser apart.
  static actorEntityId = null;

  // The entity types each count in syncCounts reads, under the same key - which types this client
  // has to hold every row of before it counts for itself.
  static syncCountTypes = {};

  // What the renders that handed pages over counted, keyed by the field and the query each ran -
  // held across page visits, so a page Back or Forward returns to finds its number, until this
  // client's own database is complete enough to count for itself.
  static syncCounts = {};

  // The identity period the held counts were carried in (see IdentityTracker).
  static syncCountsPeriod = null;

  // The identity period that was lasting when this tab was told somebody else signed in. No saved
  // count is filed while it lasts, whichever document saved it, though the page's own state is
  // still restored. The stream's frame and the responses arrive independently, so either can reach
  // a tab first, and the frame doesn't name the identity it announces, so the two orders can't be
  // told apart here.
  //
  // With the frame first, the tab's period and tag go on naming the previous user, and this is what
  // keeps that user's counts from coming back. With a response first, as after a login from this
  // tab, the period is already the new user's, and their own saved counts are refused for the rest
  // of it. A count still held keeps answering. One no longer held, like one reset() dropped or the
  // cap trimmed, doesn't come back, and the page counts the rows it has so far, which can be too
  // few during a fill.
  static identityEndedPeriod = null;

  // type -> relationship -> source id -> Set of target ids
  static #facts = {};

  // The rows held on an earlier word of the server's - a page render's, or a stream's from before
  // a resync - until this fill confirms them. What is still here when the fill declares itself
  // complete was never the client's to hold, or is no longer: a grant revoked between a render
  // and a connect, or a row deleted while the browser was away.
  static #carried = new Set();

  // The rows an answer filed while a fill was on its way, each with the number of the batch that
  // created them. Each is carried until a frame delivers it or the fill ends, so nothing stores it
  // before then. The type's marker takes away the ones whose batch the fill read and left out (see
  // #settlePromoted). The rest wait here, out of the marker's sweep, until the marker ending the
  // fill.
  static #promotedSeqs = new Map();

  // Whether the server has declared everything complete, and the entity types it has declared
  // complete before that - until a type is, the database answers a query over it with part of the
  // truth and its readers must not treat it as the whole.
  static #syncedAll = false;

  static #syncedTypes = new Set();

  // What has been marked complete since this client last changed identity, which a refill doesn't
  // take back. A number saved before the client counted a query for itself is behind what it
  // counted, even while a refill has it waiting to count again. Giving up a place counts as
  // everything marked, since the server hands one out only for a whole pot, and a document that
  // resumed from a stored place may have heard no marker yet.
  static #everSyncedAll = false;

  static #everSyncedTypes = new Set();

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

  // Every held row goes back to awaiting the server's word, because a whole fill is about to say
  // which of them are still this client's. The rows and their facts STAY - the screen goes on
  // showing them and an action can still read and write them - and the marker ending the fill
  // takes away whatever it never delivered, through the same sweep that takes away the rows a
  // page carried and the stream never vouched for.
  //
  // The completeness marks go, because nothing is complete again until a marker says so. A carried
  // count stays: it's the only number the client has for a query it can't count yet, and the first
  // greeting of a page load comes here right after the page filed its counts. Like the rows kept
  // above, it can be behind what the user may now read, until the marker of the last type it
  // reads. Counting sooner would count a table still being filled or swept. One the client has
  // been counting itself goes, while the marks still say which those are. Kept past them, it would
  // come back as a number the rows have moved on from.
  static beginRefill({hadPlace = false} = {}) {
    if (hadPlace) {
      LocalDatabase.#everSyncedAll = true;
    }

    for (const [type, table] of Object.entries(LocalDatabase.#tables)) {
      for (const id of Object.keys(table)) {
        LocalDatabase.markCarried(type, id);
      }
    }

    // A row answered before this fill's session began is in everything the fill reads, so every
    // marker covers it and it needs no number of its own. An answer can overtake a resync frame,
    // and then the marker may take away a row its session is about to judge. The session hands it
    // back after the fill when its user may read it.
    LocalDatabase.#promotedSeqs = new Map();

    LocalDatabase.#dropCountable();
    LocalDatabase.#syncedAll = false;
    LocalDatabase.#syncedTypes = new Set();
  }

  // Files the counts a page visit carried beside the ones earlier visits did. A number for a query
  // the client can already count is no use, so it isn't kept, and neither is one held from before
  // its types were marked. The oldest go when there are too many, but never the ones given here:
  // they are the numbers of the page being mounted.
  static carryCounts(counts, countTypes) {
    LocalDatabase.#dropCountable();

    for (const [key, count] of Object.entries(counts)) {
      LocalDatabase.#fileCount(key, count, countTypes[key]);
    }

    LocalDatabase.#trimCounts(new Set(Object.keys(counts)));
  }

  // The given carried counts that are still held and that the client can't count yet, as
  // [key, number, types or null], the form a page snapshot stores them in.
  static countEntries(keys) {
    const entries = [];
    let length = 0;

    for (const key of keys) {
      if (
        !Object.hasOwn(LocalDatabase.syncCounts, key) ||
        LocalDatabase.countsLocally(key)
      ) {
        continue;
      }

      length += key.length;

      if (length > SAVED_COUNT_KEYS_LENGTH_LIMIT) {
        break;
      }

      entries.push([
        key,
        LocalDatabase.syncCounts[key],
        LocalDatabase.syncCountTypes[key] ?? null,
      ]);
    }

    return entries;
  }

  // Whether the client counts the query under the given key for itself: it holds every row of each
  // type the query reads, or everything. A count carried with no types waits for everything.
  static countsLocally(key) {
    return LocalDatabase.#isCountable(LocalDatabase.syncCountTypes[key]);
  }

  static deleteFact(type, relationship, sourceId, targetId) {
    LocalDatabase.#facts[type]?.[relationship]?.[sourceId]?.delete(targetId);
  }

  // A number counted for one user must never answer for another.
  static dropCounts() {
    LocalDatabase.syncCountTypes = {};
    LocalDatabase.syncCounts = {};
  }

  // Files the counts a page snapshot saved, in the form countEntries gives them. A number already
  // held stays. It's usually from a later render, and when it isn't, both are old server counts
  // that end at the same marker. Each is filed as the newest either way, since they are the numbers
  // of the page being restored.
  static restoreCountEntries(entries) {
    LocalDatabase.#dropCountable();

    for (const [key, count, types] of entries) {
      const isHeld = Object.hasOwn(LocalDatabase.syncCounts, key);

      if (!isHeld && LocalDatabase.#wasCountable(types ?? undefined)) {
        continue;
      }

      LocalDatabase.#fileCount(
        key,
        isHeld ? LocalDatabase.syncCounts[key] : count,
        isHeld ? LocalDatabase.syncCountTypes[key] : (types ?? undefined),
      );
    }

    LocalDatabase.#trimCounts(new Set(entries.map(([key]) => key)));
  }

  // Every pair filed under a held row that names one of the given rows of the given type: in a
  // to-many of that type, and in an inverse of a to-many whose source is of that type. Answers the
  // key of every row the stream vouched for whose set lost one, which storing keeps.
  static deleteFactsNaming(type, ids) {
    const written = [];

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

        // A row a page carried is never stored, so one whose set changed isn't written either.
        if (
          changed &&
          !LocalDatabase.#carried.has(`${holderType}${SEPARATOR}${holderId}`)
        ) {
          written.push(`${holderType} ${holderId}`);
        }
      }
    }

    return written;
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

  // Whether a target set has been FILED for the triple, which is not the same as its holding
  // something. A row states the whole set of a relationship it names, empty sets included, so
  // "filed and empty" is a fact about the world and "never filed" is the absence of one - and the
  // absence is what a stored set may still speak for. `baseTargetIds` cannot tell them apart,
  // answering an empty set for both.
  static hasFacts(type, relationship, sourceId) {
    return LocalDatabase.#facts[type]?.[relationship]?.[sourceId] !== undefined;
  }

  static isAllSynced() {
    return LocalDatabase.#syncedAll;
  }

  static isTypeSynced(type) {
    return LocalDatabase.#syncedAll || LocalDatabase.#syncedTypes.has(type);
  }

  // Everything marked complete so far, as one value: whether all of it is, and which types are.
  //
  // Nothing stores it: completeness is declared by a marker on a STREAM, so a database read back at
  // a page load has been told nothing about it and starts with none, however much it holds. Which is
  // why it can be asked for whole - the answer is only ever what this run of the client has been
  // told.
  static syncedState() {
    return {
      all: LocalDatabase.#syncedAll,
      types: Array.from(LocalDatabase.#syncedTypes),
    };
  }

  static carriedEntries() {
    return Array.from(LocalDatabase.#carried, (entry) =>
      entry.split(SEPARATOR),
    );
  }

  static markCarried(type, id) {
    LocalDatabase.#carried.add(`${type}${SEPARATOR}${id}`);
  }

  // A row an answer filed while a fill is on its way, with the number of its batch. Nothing is
  // known yet of whether its user may read it, so it is carried and not stored. If its type's
  // marker is still to come and the fill read the batch without sending the row, the marker takes
  // it away. Otherwise its session judges it.
  static markPromoted(type, id, seq) {
    LocalDatabase.#promotedSeqs.set(`${type}${SEPARATOR}${id}`, seq);
    LocalDatabase.markCarried(type, id);
  }

  static unmarkCarried(type, id) {
    LocalDatabase.#carried.delete(`${type}${SEPARATOR}${id}`);
  }

  // The whole-pot marker is what makes a carried row's absence mean something: the fill is
  // complete at "all" by definition, so a row still held only because a page carried it is one
  // the server never sent - a grant revoked between that render and this connect leaves exactly
  // that. Dropped here rather than left to be read, which is the discard the resync path makes.
  //
  // Only the first time: a row a page carried since is one the stream has yet to deliver, or to be
  // told about, and a mark told again - a tab of the group posting its state on every join - is no
  // new word about it.
  static markAllSynced() {
    if (LocalDatabase.#syncedAll) {
      return;
    }

    LocalDatabase.#syncedAll = true;
    LocalDatabase.#everSyncedAll = true;

    // A row still recorded is one its session will judge, or one of a type sync doesn't send. It
    // stays as the answer filed it.
    for (const key of LocalDatabase.#promotedSeqs.keys()) {
      LocalDatabase.#carried.delete(key);
    }

    LocalDatabase.#promotedSeqs = new Map();

    LocalDatabase.#sweepCarried(() => true);
  }

  // A type's marker says the same of that type's rows: the fill sends every row of a type the
  // client may see before it, so a row of the type still held only because a page carried it, or
  // from before a refill, is one the server did not send. Swept here for the same reason, and
  // before anything counts over the type: a count would otherwise include a row deleted while the
  // browser was away.
  //
  // Only for a type marked for the first time, for the same reason the whole pot's is swept once.
  //
  // `appliedSeq` is how far this client's batches are in what the fill read of the types, which
  // settles the rows answers filed meanwhile (see #settlePromoted). A row taken away leaves the
  // sets naming it too. Answers the keys of the rows the stream vouched for whose sets lost one,
  // which storing keeps.
  static markTypesSynced(types, appliedSeq = null) {
    const marked = new Set(
      types.filter((type) => !LocalDatabase.#syncedTypes.has(type)),
    );

    for (const type of marked) {
      LocalDatabase.#syncedTypes.add(type);
      LocalDatabase.#everSyncedTypes.add(type);
    }

    LocalDatabase.#settlePromoted(marked, appliedSeq);

    const written = new Set();

    if (LocalDatabase.#syncedAll) {
      return written;
    }

    const swept = LocalDatabase.#sweepCarried(
      (type, id) =>
        marked.has(type) &&
        !LocalDatabase.#promotedSeqs.has(`${type}${SEPARATOR}${id}`),
    );

    for (const [type, ids] of swept) {
      for (const key of LocalDatabase.deleteFactsNaming(type, ids)) {
        written.add(key);
      }
    }

    return written;
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

  // The rows the STREAM vouched for, each keyed "<type> <id>" the way a frame names one - so the
  // answer is what `records` takes, and a whole database can be written down the way one frame's
  // rows are.
  //
  // A carried row is left out, which is the same rule durable storage already follows a frame at a
  // time: a page's rows are the server's word for one render, every visit carries them again, and
  // a row held only because a page carried it is one a completeness marker may yet take away.
  static vouchedRowKeys() {
    const rowKeys = new Set();

    for (const [type, table] of Object.entries(LocalDatabase.#tables)) {
      for (const id of Object.keys(table)) {
        if (!LocalDatabase.#carried.has(`${type}${SEPARATOR}${id}`)) {
          rowKeys.add(`${type} ${id}`);
        }
      }
    }

    return rowKeys;
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

  // Fills the database with what a previous page load left in durable storage, WITHOUT disturbing
  // anything this page already carried.
  //
  // What the page carried is the fresher of the two by construction: the server rendered it for
  // this request, and these records were written from frames that arrived before the last unload.
  // So a row the page brought wins on its values, and a stored row fills only an id the page said
  // nothing about. Facts are the one place a stored record still has something to add to a held
  // row: a page's row states the target sets of the relationships its query included and stays
  // silent about the rest, and a set nobody has filed is one the stored record may speak for.
  //
  // A held row is also unmarked as carried, because holding a stored record for it IS the evidence
  // the stream vouched for it on an earlier load. Left marked, it would be swept the moment the
  // server declares the pot complete - and a resuming client is told only what changed while it
  // was away, so nothing would resend it.
  static restore(records) {
    for (const record of records) {
      // A snapshot of a gone row is never written down, and the shape allows one, so it is passed
      // over rather than filed as a row with nothing in it.
      if (record.row === null) {
        continue;
      }

      const {facts, id, row, type} = record;

      if (LocalDatabase.baseRow(type, id) === null) {
        LocalDatabase.putRow(type, row);
      } else {
        LocalDatabase.unmarkCarried(type, id);
      }

      for (const [relationship, targetIds] of Object.entries(facts)) {
        if (!LocalDatabase.hasFacts(type, relationship, id)) {
          LocalDatabase.replaceFacts(type, relationship, id, targetIds);
        }
      }
    }
  }

  // The overlay is deliberately NOT reset here. This runs on a resync, which replaces what the
  // SERVER said - and what this client has written and not yet sent is not the server's to take
  // away. Overlay.reset() exists for the callers that do mean it.
  static reset() {
    LocalDatabase.dropCounts();
    LocalDatabase.syncCountsPeriod = null;
    LocalDatabase.identityEndedPeriod = IdentityTracker.period;
    LocalDatabase.#everSyncedAll = false;
    LocalDatabase.#everSyncedTypes = new Set();
    LocalDatabase.#carried = new Set();
    LocalDatabase.#facts = {};
    LocalDatabase.#promotedSeqs = new Map();
    LocalDatabase.#syncedAll = false;
    LocalDatabase.#syncedTypes = new Set();
    LocalDatabase.#tables = {};
  }

  static #dropCountable() {
    for (const key of Object.keys(LocalDatabase.syncCounts)) {
      if (LocalDatabase.countsLocally(key)) {
        LocalDatabase.#forgetCount(key);
      }
    }
  }

  // Deleted first, so that a number filed again counts as the newest.
  static #fileCount(key, count, types) {
    LocalDatabase.#forgetCount(key);

    if (LocalDatabase.#isCountable(types)) {
      return;
    }

    LocalDatabase.syncCounts[key] = count;

    if (types !== undefined) {
      LocalDatabase.syncCountTypes[key] = types;
    }
  }

  static #forgetCount(key) {
    delete LocalDatabase.syncCounts[key];
    delete LocalDatabase.syncCountTypes[key];
  }

  static #isCountable(types) {
    return (
      LocalDatabase.#syncedAll ||
      (types !== undefined &&
        types.every((type) => LocalDatabase.#syncedTypes.has(type)))
    );
  }

  // Oldest first, which is the order the keys are in. The kept ones were filed last, so the walk
  // ends at the first of them.
  static #trimCounts(kept) {
    const keys = Object.keys(LocalDatabase.syncCounts);

    let excess = keys.length - CARRIED_COUNTS_LIMIT;
    let length = keys.reduce((sum, key) => sum + key.length, 0);

    for (const key of keys) {
      if (
        kept.has(key) ||
        (excess <= 0 && length <= CARRIED_COUNT_KEYS_LENGTH_LIMIT)
      ) {
        return;
      }

      LocalDatabase.#forgetCount(key);

      excess -= 1;
      length -= key.length;
    }
  }

  static #wasCountable(types) {
    return (
      LocalDatabase.#everSyncedAll ||
      (types !== undefined &&
        types.every((type) => LocalDatabase.#everSyncedTypes.has(type)))
    );
  }

  // What a marker makes of the rows answers filed while the given types were being filled. One
  // whose batch is at or below the number was in what the fill read, so unless a frame delivered
  // it, the row is gone or its user may not read it. It stops being recorded, and the marker's
  // sweep takes it if it is still carried. One above the number committed after the read, so its
  // session judges it, and a marker naming no number makes no claim. Those stay recorded.
  static #settlePromoted(types, appliedSeq) {
    if (!Number.isInteger(appliedSeq)) {
      return;
    }

    for (const [key, seq] of LocalDatabase.#promotedSeqs) {
      const type = key.slice(0, key.indexOf(SEPARATOR));

      if (types.has(type) && seq <= appliedSeq) {
        LocalDatabase.#promotedSeqs.delete(key);
      }
    }
  }

  // The carried rows the given test picks, taken away and unmarked. Answers their ids, per type.
  static #sweepCarried(picks) {
    const swept = new Map();

    for (const [type, id] of LocalDatabase.carriedEntries()) {
      if (picks(type, id)) {
        LocalDatabase.deleteRow(type, id);
        LocalDatabase.unmarkCarried(type, id);

        if (!swept.has(type)) {
          swept.set(type, new Set());
        }

        swept.get(type).add(id);
      }
    }

    return swept;
  }

  // The facts a row is filed with: its to-many relationships', and its inverses' of a to-many.
  //
  // A relationship nothing has FILED a set for is left out, rather than written down as empty.
  // `baseTargetIds` answers an empty set for both, so storing what it returns would turn "nobody
  // has said" into "the server said none" - an assertion nobody made, which `restore` would then
  // act on by filing it. The two are told apart by `hasFacts`, and the whole point of that
  // distinction is lost if the snapshot flattens it.
  static #toManyFacts(type, id) {
    const facts = {};

    const factNames = Object.entries(Model.relationships(type))
      .filter(([_name, relationship]) => relationship.toMany)
      .concat(
        Object.entries(Model.inverses(type)).filter(
          ([_name, inverse]) => !inverse.reference,
        ),
      )
      .map(([name]) => name);

    for (const name of factNames) {
      if (LocalDatabase.hasFacts(type, name, id)) {
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

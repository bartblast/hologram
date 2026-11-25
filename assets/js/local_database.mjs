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

// What a put spells a row the client's own batch created with, beside its data (see
// Hologram.Sync.Frame.put_entity/3).
const OWN = "$own";

// The numbers that place a row in the server's order, which a row holds only once they are final.
const SEQUENCE_FIELDS = ["server_created_seq", "server_updated_seq"];

export default class LocalDatabase {
  // Who the client is, the session's user id as it is - nil for a visitor. It names whose rows and
  // queued writes this database holds. It arrives with the page rather than with the rows, and a
  // resync does not clear it: what the client may see can change without anyone becoming someone
  // else.
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

  // How many times anything was filed here, which lets a reader of every id skip reading them again
  // (see `filings`). A reset leaves it: a reset adds no id, and whatever is filed after one moves it.
  static #filings = 0;

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

  // type -> relationship -> source id -> Set of the ids its stored set names and the set held here
  // doesn't: a set a page filed is the fresher, so restoring leaves it and the stored one stays as
  // it was. A pair a cut stream left there would come back on a later page load, so a drop naming
  // one takes it out of the stored set too (see `takeStoredFactRemovals`). Only the pair: the
  // holder held here can be older than the stored one, so it isn't written over it.
  static #storedOnlyFacts = {};

  // What the last frame took out of stored sets, each `{id, relationship, targetIds, type}`, until
  // the tab storing that frame takes it.
  static #storedFactRemovals = [];

  // What has been marked complete since this client last changed identity, which a refill doesn't
  // take back. A number saved before the client counted a query for itself is behind what it
  // counted, even while a refill has it waiting to count again. Giving up a place counts as
  // everything marked, since the server hands one out only for a whole pot, and a document that
  // resumed from a stored place may have heard no marker yet.
  static #everSyncedAll = false;

  static #everSyncedTypes = new Set();

  // type -> id -> row
  static #tables = {};

  // How far every number the client holds is final: it holds every row it may read whose number is
  // at or below it, so a row numbered above it can still be followed by one numbered below, which
  // would sort ahead of it. The highest the server told, whichever node told it - each works out
  // its own - until the log the numbers come from is another (see `forgetFinal`).
  static #finalSeq = null;

  // type -> number: how far a fill's marker made the numbers of its type final, while the fill
  // that sent it runs. The marker carries the fill's one point, but only for its own type: the
  // rows of a type still to come arrive in no number order, so until its marker a number at or
  // below the point can still be followed by a lower one. The marker ending the fill makes the
  // point every type's, and anything that resets or replaces the final point drops them (see
  // #dropTypeFinals).
  static #typeFinalSeqs = {};

  // type -> id -> {numbers: {field: number}, shown?: {field: number}, own: boolean} - each number
  // a row came with above the final point, held back from the row until the point reaches it. The
  // row holds the number it had before, final, or null when it had none, so a number a reader
  // finds is always final and no reader has to ask. Shown is the numbers a page carried above the
  // point: final on the server, so a list orders the row by them (see orderingKey). Own is whether
  // the row's own batch created it, kept while its created number waits: until then it is this
  // client's own unnumbered row.
  static #waiting = {};

  static addFact(type, relationship, sourceId, targetId) {
    LocalDatabase.#filings += 1;
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
    LocalDatabase.#dropTypeFinals();
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
  //
  // Given `writeHolders: false`, for ids the client no longer holds a row of or never did, it answers
  // none and queues each pair to be taken out of the stored set alone (see
  // `takeStoredFactRemovals`). The holder held here can come from a page older than its stored
  // record, and such a pair is no reason to write it over that record.
  static deleteFactsNaming(type, ids, {writeHolders = true} = {}) {
    if (ids.size === 0) {
      return [];
    }

    const written = [];

    for (const [holderType, names] of LocalDatabase.#setsNaming(type)) {
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

          LocalDatabase.#queueStoredRemoval(
            holderType,
            name,
            holderId,
            ids,
            writeHolders ? [] : named,
          );
        }

        // A row a page carried is never stored, so one whose set changed isn't written either.
        if (
          writeHolders &&
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

    delete LocalDatabase.#waiting[type]?.[id];

    const typeFacts = LocalDatabase.#facts[type];

    if (typeFacts) {
      for (const relationship of Object.keys(typeFacts)) {
        delete typeFacts[relationship][id];
      }
    }

    for (const relationshipFacts of Object.values(
      LocalDatabase.#storedOnlyFacts[type] ?? {},
    )) {
      delete relationshipFacts[id];
    }
  }

  // The given row a page carried as the base files it: a copy with every number above the final
  // point replaced by the one the row already holds, or null, as a stream row's is (see
  // holdNumbers). The render showed only numbers final on the server, so each is kept beside the
  // row as shown, and a list orders the row by it while the field reads as not final here (see
  // orderingKey). A number at or below the point is the stream's to bring for a row held already.
  static carryNumbers(type, row) {
    const filed = Object.assign({}, row);

    delete filed[OWN];

    const held = LocalDatabase.baseRow(type, row.id);

    for (const field of SEQUENCE_FIELDS) {
      if (
        !Object.hasOwn(row, field) ||
        LocalDatabase.#isFinal(type, row[field])
      ) {
        continue;
      }

      filed[field] = held?.[field] ?? null;

      LocalDatabase.#show(type, row.id, field, row[field]);
    }

    LocalDatabase.#settleEntry(type, row.id);

    return filed;
  }

  // How far the numbers the client holds are final, or null when it was told nothing yet.
  static finalSeq() {
    return LocalDatabase.#finalSeq;
  }

  // Forgets how far the numbers are final, the numbers waiting for it and the numbers the rows
  // hold: the log they came from is gone, and a log claimed again numbers its saves from the start,
  // so none of them says anything about the numbers that follow. A row kept its number in place of
  // one that waits, and a stored waiting number is taken up only over an older one, so a number of
  // the lost log left in a row would stay there past the refill. Each row goes on a copy, since
  // readers hold the rows they were handed.
  static forgetFinal() {
    LocalDatabase.#finalSeq = null;
    LocalDatabase.#dropTypeFinals();
    LocalDatabase.#waiting = {};

    for (const [type, table] of Object.entries(LocalDatabase.#tables)) {
      for (const row of Object.values(table)) {
        const numbered = SEQUENCE_FIELDS.filter(
          (field) => (row[field] ?? null) !== null,
        );

        if (numbered.length > 0) {
          const copy = Object.assign({}, row);

          for (const field of numbered) {
            copy[field] = null;
          }

          LocalDatabase.putRow(type, copy);
        }
      }
    }
  }

  // The given row or patch as the base files it, a copy with every number above the final point
  // held back: the copy carries the number the row already holds in its place, or null, and the
  // number waits beside the row (see #waiting). A number at or below the point is filed as it
  // came, leaving one waiting for the same field to wait: a waiting number is above the point, so
  // it is the newer of the two, which a delivery sent again from an older place can put second.
  // The own flag doesn't reach the row.
  static holdNumbers(type, item) {
    const filed = Object.assign({}, item);

    delete filed[OWN];

    const held = LocalDatabase.baseRow(type, item.id);
    const entry = LocalDatabase.#waitingEntry(type, item.id);

    for (const field of SEQUENCE_FIELDS) {
      if (!Object.hasOwn(item, field)) {
        continue;
      }

      if (!LocalDatabase.#isFinal(type, item[field])) {
        entry.numbers[field] = item[field];
        filed[field] = held?.[field] ?? null;
      }
    }

    entry.own ||= item[OWN] === true;

    LocalDatabase.#settleEntry(type, item.id);

    return filed;
  }

  // Moves the final point up to the given one, and files every waiting number it now reaches into
  // its row. A point at or below the one held moves nothing: another node can be behind this one.
  static raiseFinal(finalSeq) {
    if (
      finalSeq === null ||
      finalSeq === undefined ||
      (LocalDatabase.#finalSeq !== null &&
        BigInt(finalSeq) <= BigInt(LocalDatabase.#finalSeq))
    ) {
      return;
    }

    LocalDatabase.#finalSeq = finalSeq;

    LocalDatabase.#fileFinal();
  }

  // Moves the final point of each given type up to the given one, for the rest of the fill whose
  // marker named them, and files every waiting number of theirs it now reaches. A point the one
  // held for everything reaches adds nothing.
  static raiseTypeFinal(types, finalSeq) {
    if (finalSeq === null || finalSeq === undefined) {
      return;
    }

    for (const type of types) {
      if (!LocalDatabase.#isFinal(type, finalSeq)) {
        LocalDatabase.#typeFinalSeqs[type] = finalSeq;
      }
    }

    LocalDatabase.#fileFinal();
  }

  // Whether the field is one of the numbers a save is given, which a list orders by the rule in
  // orderingKey.
  static isSequenceField(name) {
    return SEQUENCE_FIELDS.includes(name);
  }

  // Where a row stands in a list ordered by one of its numbers, as `[rank, number]`, lowest first:
  // 0 for a number final here or one a page showed, 1 for no number known, 2 for a row this
  // client's own batch created, ordered among its kind by the number it waits for, and 3 for a row
  // the server has not saved yet. A row whose number isn't final here goes at the newest end, since
  // its number is above every final one, and so does this client's own work, which is newer still.
  static orderingKey(type, row, field) {
    const value = row[field] ?? null;
    const entry = LocalDatabase.#waiting[type]?.[row.id];
    const shown = entry?.shown?.[field];

    if (
      shown !== undefined &&
      (value === null || BigInt(shown) > BigInt(value))
    ) {
      return [0, LocalDatabase.#readNumber(shown)];
    }

    if (value !== null) {
      return [0, value];
    }

    if (entry?.own) {
      return [
        2,
        LocalDatabase.#readNumber(
          entry.numbers[field] ?? entry.numbers.server_created_seq,
        ),
      ];
    }

    return [(row.server_created_at ?? null) === null ? 3 : 1, null];
  }

  // The numbers the given row waits for, as `{numbers, own}` with the ones a page showed as
  // `shown`, or null when it waits for none.
  static waitingNumbers(type, id) {
    return LocalDatabase.#waiting[type]?.[id] ?? null;
  }

  // Answers a number that moves whenever a row or a pair is filed, so a caller holding what it read
  // of every id can tell whether reading them again could find a new one.
  static filings() {
    return LocalDatabase.#filings;
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

  // The ids of the given type the client holds a row of, or finds in a set of a row it holds, here
  // or in that set's stored copy. A set can name a row that never arrived or has already left: a
  // stream cut inside a batch or a catch-up leaves such a pair, and only a drop by hash or a keep
  // list can reach it afterwards, since the server doesn't know the client has it.
  static heldOrNamedIds(type) {
    const ids = new Set(Object.keys(LocalDatabase.baseTable(type)));

    for (const [holderType, names] of LocalDatabase.#setsNaming(type)) {
      for (const holderId of Object.keys(LocalDatabase.baseTable(holderType))) {
        for (const name of names) {
          for (const targetId of LocalDatabase.baseTargetIds(
            holderType,
            name,
            holderId,
          )) {
            ids.add(targetId);
          }

          const storedOnly =
            LocalDatabase.#storedOnlyFacts[holderType]?.[name]?.[holderId];

          for (const targetId of storedOnly ?? []) {
            ids.add(targetId);
          }
        }
      }
    }

    return ids;
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
    LocalDatabase.#dropTypeFinals();

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

    // This marker also ends a catch-up, whose store was never cleared, so a pair naming a swept row
    // can be stored. Only the pair leaves it, as for a row dropped by id (see Deltas.apply).
    const swept = LocalDatabase.#sweepCarried(() => true);

    for (const [type, ids] of swept) {
      LocalDatabase.deleteFactsNaming(type, ids, {writeHolders: false});
    }
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
    LocalDatabase.#filings += 1;

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
  //
  // The numbers a row waits for ride beside it as `waiting`, so the next page load holds them back
  // the way this one does (see `restore`).
  static records(rowKeys) {
    return Array.from(rowKeys, (rowKey) => {
      const separator = rowKey.indexOf(" ");
      const type = rowKey.slice(0, separator);
      const id = rowKey.slice(separator + 1);
      const row = LocalDatabase.baseRow(type, id);

      if (row === null) {
        return {id, row: null, type};
      }

      const record = {
        facts: LocalDatabase.#toManyFacts(type, id),
        id,
        row,
        type,
      };
      const waiting = LocalDatabase.waitingNumbers(type, id);

      return waiting === null
        ? record
        : {...record, waiting: LocalDatabase.#copyEntry(waiting)};
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

  // Answers what the last frame took out of stored sets, for the tab storing it, and forgets it. A
  // tab that doesn't store frames never takes it, so each frame starts by discarding what the one
  // before left: kept, it could take out a pair a later frame told again.
  static takeStoredFactRemovals() {
    const removals = LocalDatabase.#storedFactRemovals;

    LocalDatabase.#storedFactRemovals = [];

    return removals;
  }

  // The whole current target set for one (source, relationship) - the snapshot statement a row's
  // id list carries, replacing whatever pairs were held before.
  static replaceFacts(type, relationship, sourceId, targetIds) {
    LocalDatabase.#filings += 1;

    delete LocalDatabase.#storedOnlyFacts[type]?.[relationship]?.[sourceId];

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
  //
  // The final point comes in with the records, since it was written down with them, and so do the
  // numbers they wait for. A row the page brought takes a stored number only when it is newer than
  // the one the row holds, which a number the page's render could not call final yet is, and a
  // created number the stored copy of the row holds where the page's holds none (see
  // #takeStoredCreated).
  // A stored row can hold a number the stored point doesn't reach, which goes back beside it (see
  // #holdStoredAbove).
  static restore(records, finalSeq = null) {
    LocalDatabase.raiseFinal(finalSeq);

    for (const record of records) {
      // A snapshot of a gone row is never written down, and the shape allows one, so it is passed
      // over rather than filed as a row with nothing in it.
      if (record.row === null) {
        continue;
      }

      const {facts, id, row, type} = record;

      const stored = LocalDatabase.baseRow(type, id) === null;

      if (stored) {
        LocalDatabase.putRow(type, row);
      } else {
        LocalDatabase.unmarkCarried(type, id);
        LocalDatabase.#takeStoredCreated(type, id, row);
      }

      LocalDatabase.#takeWaiting(type, id, record.waiting);

      if (stored) {
        LocalDatabase.#holdStoredAbove(type, id);
      }

      for (const [relationship, targetIds] of Object.entries(facts)) {
        if (!LocalDatabase.hasFacts(type, relationship, id)) {
          LocalDatabase.replaceFacts(type, relationship, id, targetIds);
        } else {
          LocalDatabase.#noteStoredOnly(type, relationship, id, targetIds);
        }
      }
    }

    LocalDatabase.#fileFinal();
  }

  // Files a row the store holds as the store holds it, over anything held under its id, with the
  // numbers the store says it waits for - what a tab taking up the store's place does with each of
  // its rows (see Tabs.#takeStore), after `takeStoredFinal`. The numbers this tab's page showed
  // stay, since they are final on the server whatever the store holds: a list keeps ordering the
  // row by them. They are the ones held beside the row now, and the given ones, which
  // `shownNumbers` took before the row was dropped. A number the store's point doesn't reach goes
  // back beside the row, as `restore` does with it.
  static putStored(type, row, waiting, shown = {}) {
    const kept = Object.entries(
      Object.assign({}, LocalDatabase.#waiting[type]?.[row.id]?.shown),
    ).concat(Object.entries(shown));

    LocalDatabase.putRow(type, row);

    delete LocalDatabase.#waiting[type]?.[row.id];

    for (const [field, number] of kept) {
      LocalDatabase.#show(type, row.id, field, number);
    }

    LocalDatabase.#takeWaiting(type, row.id, waiting);
    LocalDatabase.#holdStoredAbove(type, row.id);

    // Only this row's numbers can have changed, and a take-up puts every stored row this way, so
    // settling the whole waiting list here would cost rows times entries.
    const entry = LocalDatabase.#waiting[type]?.[row.id];

    if (entry !== undefined) {
      LocalDatabase.#fileEntry(type, row.id, entry);
    }
  }

  // The numbers a page showed for each row, keyed "<type> <id>" as vouchedRowKeys are, for a tab
  // about to drop the rows it holds and take up the store's (see putStored).
  static shownNumbers() {
    const shown = new Map();

    for (const [type, entries] of Object.entries(LocalDatabase.#waiting)) {
      for (const [id, entry] of Object.entries(entries)) {
        if (entry.shown !== undefined) {
          shown.set(`${type} ${id}`, Object.assign({}, entry.shown));
        }
      }
    }

    return shown;
  }

  // Takes up the final point the store holds, in place of the one held: the rows held from now on
  // are the store's, and its point is the one written down with them. A row only a page carried
  // stays, and a number of its filed under a higher point than the store's moves back beside it as
  // shown, so a number in a row is still final here.
  static takeStoredFinal(finalSeq) {
    LocalDatabase.#finalSeq = finalSeq ?? null;
    LocalDatabase.#dropTypeFinals();

    for (const [type, id] of LocalDatabase.carriedEntries()) {
      const held = LocalDatabase.baseRow(type, id);

      if (held === null) {
        continue;
      }

      const above = SEQUENCE_FIELDS.filter(
        (field) =>
          (held[field] ?? null) !== null &&
          !LocalDatabase.#isFinal(type, held[field]),
      );

      if (above.length === 0) {
        continue;
      }

      const row = Object.assign({}, held);

      for (const field of above) {
        LocalDatabase.#show(type, id, field, held[field]);
        row[field] = null;
      }

      LocalDatabase.putRow(type, row);
    }

    // A number the page showed can be final under the store's point: the stored rows put after
    // this settle only themselves (see putStored).
    LocalDatabase.#fileFinal();
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
    LocalDatabase.#finalSeq = null;
    LocalDatabase.#promotedSeqs = new Map();
    LocalDatabase.#storedFactRemovals = [];
    LocalDatabase.#storedOnlyFacts = {};
    LocalDatabase.#syncedAll = false;
    LocalDatabase.#syncedTypes = new Set();
    LocalDatabase.#tables = {};
    LocalDatabase.#typeFinalSeqs = {};
    LocalDatabase.#waiting = {};
  }

  static #copyEntry(entry) {
    const copy = {numbers: Object.assign({}, entry.numbers), own: entry.own};

    if (entry.shown !== undefined) {
      copy.shown = Object.assign({}, entry.shown);
    }

    return copy;
  }

  // The points a fill's markers gave their types go once the fill is over, or another starts: the
  // marker ending it makes its point everyone's, and a fill begun again says nothing of a type until
  // its own marker.
  static #dropTypeFinals() {
    LocalDatabase.#typeFinalSeqs = {};
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

  // Queues the given ids taken out of a set here, and those of the given ids only its stored copy
  // names, to be taken out of the stored set when the frame is stored.
  static #queueStoredRemoval(type, relationship, sourceId, ids, removedIds) {
    const storedOnly =
      LocalDatabase.#storedOnlyFacts[type]?.[relationship]?.[sourceId];

    const storedOnlyIds = Array.from(storedOnly ?? []).filter((id) =>
      ids.has(id),
    );

    for (const id of storedOnlyIds) {
      storedOnly.delete(id);
    }

    const targetIds = removedIds.concat(storedOnlyIds);

    if (targetIds.length === 0) {
      return;
    }

    LocalDatabase.#storedFactRemovals.push({
      id: sourceId,
      relationship,
      targetIds,
      type,
    });
  }

  static #noteStoredOnly(type, relationship, sourceId, storedIds) {
    const held = LocalDatabase.baseTargetIds(type, relationship, sourceId);
    const storedOnly = storedIds.filter((id) => !held.has(id));

    if (storedOnly.length === 0) {
      return;
    }

    LocalDatabase.#filings += 1;

    const typeFacts = (LocalDatabase.#storedOnlyFacts[type] ??= {});
    const relationshipFacts = (typeFacts[relationship] ??= {});

    relationshipFacts[sourceId] = new Set(storedOnly);
  }

  // The sets that can name a row of the given type, as `[holder type, names]`: its to-manys pointing
  // at the type, and its inverses of a to-many whose source is of the type.
  static #setsNaming(type) {
    const sets = [];

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

      if (names.length > 0) {
        sets.push([holderType, names]);
      }
    }

    return sets;
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

  // Files every waiting or shown number at or below the final point into its row, the higher of
  // the two when both are, on a copy of the row, since readers hold the rows they were handed. A
  // shown number can be filed while a newer one waits: it is final, and older than what waits.
  static #fileFinal() {
    for (const [type, entries] of Object.entries(LocalDatabase.#waiting)) {
      for (const [id, entry] of Object.entries(entries)) {
        LocalDatabase.#fileEntry(type, id, entry);
      }
    }
  }

  // Files one row's waiting or shown numbers at or below the final point, as #fileFinal does for
  // every row.
  static #fileEntry(type, id, entry) {
    const held = LocalDatabase.baseRow(type, id);

    if (held === null) {
      return;
    }

    let row = null;

    for (const field of SEQUENCE_FIELDS) {
      let filed = null;

      for (const numbers of [entry.numbers, entry.shown ?? {}]) {
        const number = numbers[field];

        if (number !== undefined && LocalDatabase.#isFinal(type, number)) {
          delete numbers[field];

          if (filed === null || BigInt(number) > BigInt(filed)) {
            filed = number;
          }
        }
      }

      const current = held[field] ?? null;

      if (
        filed !== null &&
        (current === null || BigInt(filed) > BigInt(current))
      ) {
        row ??= Object.assign({}, held);
        row[field] = filed;
      }
    }

    if (row !== null) {
      LocalDatabase.putRow(type, Model.readIntegers(type, row));
    }

    LocalDatabase.#settleEntry(type, id);
  }

  // Moves each number a stored row holds above the point back beside it, unless a newer one waits
  // there already. A frame naming no place is stored with its rows filed under the point held then,
  // while the point stored stays the one written with the last place (see Durability.persistFrame).
  // Kept in the row, such a number would be one a reader finds while an older one stored beside
  // another row still waits, and a count from it would never take that older one in.
  static #holdStoredAbove(type, id) {
    const held = LocalDatabase.baseRow(type, id);

    const above = SEQUENCE_FIELDS.filter(
      (field) =>
        (held[field] ?? null) !== null &&
        !LocalDatabase.#isFinal(type, held[field]),
    );

    if (above.length === 0) {
      return;
    }

    const row = Object.assign({}, held);
    const entry = LocalDatabase.#waitingEntry(type, id);

    for (const field of above) {
      const waiting = entry.numbers[field];

      if (waiting === undefined || BigInt(waiting) < BigInt(held[field])) {
        entry.numbers[field] = held[field];
      }

      row[field] = null;
    }

    LocalDatabase.putRow(type, row);
  }

  // A waiting number as the wire spelled it, which is a string past 2^53.
  static #readNumber(number) {
    return typeof number === "string" ? BigInt(number) : (number ?? null);
  }

  // Whether a number of the given type is final here: at or below the point every type has, or the
  // one its type's marker gave it in the fill running now.
  static #isFinal(type, number) {
    if (number === null || number === undefined) {
      return true;
    }

    return [
      LocalDatabase.#finalSeq,
      LocalDatabase.#typeFinalSeqs[type] ?? null,
    ].some((point) => point !== null && BigInt(number) <= BigInt(point));
  }

  // A row whose created number is final is numbered, so it is no longer anybody's own, and an entry
  // waiting for nothing goes.
  static #settleEntry(type, id) {
    const entries = LocalDatabase.#waiting[type];
    const entry = entries?.[id];

    if (entry === undefined) {
      return;
    }

    if (!Object.hasOwn(entry.numbers, "server_created_seq")) {
      entry.own = false;
    }

    if (entry.shown !== undefined && Object.keys(entry.shown).length === 0) {
      delete entry.shown;
    }

    if (Object.keys(entry.numbers).length === 0 && entry.shown === undefined) {
      delete entries[id];
    }
  }

  // Keeps a number a page showed beside the row, unless one it showed before is newer.
  static #show(type, id, field, number) {
    const entry = LocalDatabase.#waitingEntry(type, id);
    const shown = entry.shown?.[field];

    if (shown === undefined || BigInt(number) > BigInt(shown)) {
      entry.shown ??= {};
      entry.shown[field] = number;
    }
  }

  // Takes the created number a stored row holds where the page's copy of it holds none, as a number
  // it waits for. The page's render can hide a number its pin didn't reach - on a node behind this
  // one, or one that just restarted - and the change that gave it can lie at or below the place
  // this page resumes from, so nothing sends it again.
  //
  // Only the created number, because it never changes for a row: a stored updated number can be an
  // older version's, which filed under the page's version would pass comparisons that version's own
  // number fails, and a timestamp can't tell two writes in the same millisecond apart. A number the
  // page showed beside the row is the page's, so a stored one no newer than it adds nothing.
  static #takeStoredCreated(type, id, stored) {
    const field = "server_created_seq";
    const number = stored[field] ?? null;

    if (
      number === null ||
      (LocalDatabase.baseRow(type, id)[field] ?? null) !== null
    ) {
      return;
    }

    const shown = LocalDatabase.#waiting[type]?.[id]?.shown?.[field];

    if (shown !== undefined && BigInt(shown) >= BigInt(number)) {
      return;
    }

    const entry = LocalDatabase.#waitingEntry(type, id);
    const waiting = entry.numbers[field];

    if (waiting === undefined || BigInt(waiting) < BigInt(number)) {
      entry.numbers[field] = number;
    }
  }

  // Takes the stored numbers a held row waits for, each only when the row holds an older one for
  // the field, or none, and no page showed one for it at least as new: that one is the version the
  // row holds, and an older version's number filed under it would pass comparisons its own fails.
  static #takeWaiting(type, id, stored) {
    if (stored === undefined || stored === null) {
      return;
    }

    const row = LocalDatabase.baseRow(type, id);
    const entry = LocalDatabase.#waitingEntry(type, id);

    for (const [field, number] of Object.entries(stored.numbers)) {
      const held = row[field];
      const shown = entry.shown?.[field];

      if (
        (held === null ||
          held === undefined ||
          BigInt(held) < BigInt(number)) &&
        (shown === undefined || BigInt(shown) < BigInt(number))
      ) {
        entry.numbers[field] = number;
      }
    }

    for (const [field, number] of Object.entries(stored.shown ?? {})) {
      const held = row[field];

      if (
        held === null ||
        held === undefined ||
        BigInt(held) < BigInt(number)
      ) {
        LocalDatabase.#show(type, id, field, number);
      }
    }

    entry.own ||= stored.own === true;

    LocalDatabase.#settleEntry(type, id);
  }

  static #waitingEntry(type, id) {
    let entries = LocalDatabase.#waiting[type];

    if (!entries) {
      entries = {};
      LocalDatabase.#waiting[type] = entries;
    }

    entries[id] ??= {numbers: {}, own: false};

    return entries[id];
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

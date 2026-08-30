"use strict";

import Clock from "./clock.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";

// What this browser keeps between page loads, and where it keeps it.
//
// Memory stays canonical: every read a query, a policy check or an action makes is answered by
// LocalDatabase and the overlay, exactly as before. This writes BEHIND memory and reads only at
// startup, so nothing on the hot path waits for a disk.
//
// What is written down is only what the STREAM delivered - a frame's rows, and the place in the
// log those rows are dated at, in one transaction so a crash cannot leave a place claiming rows
// that were never written. A row a page carried is not written: every page visit carries it again.
// A row a confirmed batch promoted is not written either: the server sends its own frame for that
// change, and a client cut off before it arrives is dated before the batch and replays it.
//
// Beside the rows it holds what this BROWSER did rather than what the server said - the replica
// identity, the batch counter and the clock. Those outlive a resync, a model change and somebody
// else signing in, because none of the three makes them untrue: a number reused is a batch the
// server answers from the record of a different batch, and a clock restarted low is a write the
// server reads as moved.
//
// They do NOT outlive a storage failure, and that is the one exception. After one, this page goes
// on spending numbers that nothing records, so a stored counter is stale rather than merely old -
// and a later load resuming from it would hand out numbers already answered. Absent is safe where
// stale is not.
//
// Where the browser offers no durable storage - private browsing, an odd embedder, a failed
// transaction - the whole thing degrades to memory mode: fully functional, and honest about it
// through `mode`.
const DATABASE_NAME = "hologram";
const ENTITIES = "entities";
const META = "meta";
const VERSION = 1;

export default class Durability {
  // Transactions started and not yet complete. A test waits on it, and a devtools panel reads it -
  // nothing in the framework does.
  static inFlight = 0;

  // "indexeddb" once a database is open, "memory" before that and after anything goes wrong.
  static mode = "memory";

  static #db = null;

  // What open() read, held until restore() consumes it. Read at open so that restore has nothing
  // to await: it runs after the page has mounted, and everything after the mount happens in one
  // continuation, before an action could dispatch and write.
  static #loaded = null;

  // Drops what the SERVER said and keeps what this browser did: the rows go, the place they were
  // dated at goes with them, and the identity, the counter and the clock stay. Called when a
  // resync replaces the whole pot, and when what is stored cannot be read by this page.
  static clear() {
    return Durability.#write([ENTITIES, META], Durability.#wipe);
  }

  // Answers nothing, and never throws: a browser that cannot store is a browser that carries on
  // from memory. Every way that can happen is named, because the reason is what a developer needs
  // when a page is unexpectedly re-downloading everything.
  static async open() {
    if (!globalThis.Hologram.sync) {
      return Durability.#memoryMode("no data model");
    }

    // Reaching the API AT ALL is inside the try, not only awaiting its answer. Where storage is
    // restricted - a sandboxed iframe, an opaque origin, a browser told to block site data - both
    // the property read and the open() call throw SYNCHRONOUSLY, and a throw escaping here would
    // not merely cost this page its durability: the runtime awaits this during boot, so the whole
    // page would fail to start in exactly the context this function exists to absorb.
    try {
      if (!globalThis.indexedDB) {
        return Durability.#memoryMode("IndexedDB unavailable");
      }

      const request = globalThis.indexedDB.open(DATABASE_NAME, VERSION);

      request.onupgradeneeded = () => Durability.#upgrade(request.result);

      Durability.#db = await Durability.#request(request);
    } catch (error) {
      return Durability.#memoryMode(`open failed (${error})`);
    }

    // Another tab is trying to move the database to a version this bundle does not speak, and
    // holding it open would block that tab indefinitely. Letting go costs this page its durability
    // and nothing else.
    Durability.#db.onversionchange = () => Durability.#fail("version change");

    Durability.mode = "indexeddb";

    try {
      Durability.#loaded = await Durability.#load();
    } catch (error) {
      return Durability.#memoryMode(`read failed (${error})`);
    }
  }

  // The number this browser has counted its batches up to, and where its clock stands.
  //
  // The ONE write anything waits for. A batch is identified by its replica and its number, and the
  // server answers a number it has already seen from its record rather than applying it again - so
  // a number handed out but never written down is a number the next page load hands out a second
  // time, and the batch carrying it is answered with what the FIRST batch got. A crash between
  // sealing a batch and storing its number loses a batch that was never sent, which is the cheap
  // side of that trade.
  //
  // One number and one clock for the whole browser, not one per tab (D1, ruled 2026-08-30): a
  // person has one replica, and the log should read that way. Until the multi-tab work takes the
  // number under a lock, two tabs writing at the same moment can hand out the same one.
  static persistCounter(seq) {
    return Durability.#write([META], (transaction) => {
      const meta = transaction.objectStore(META);

      meta.put(seq, "seq");
      meta.put(Clock.last(), "clock");
    });
  }

  // One frame, one transaction: the rows it wrote, the place those rows are dated at, and where
  // the clock now stands. Together, because a place is a claim about rows - stored apart, a crash
  // between them would leave a client naming a place it does not hold the rows for, and the server
  // would tell it only what changed since.
  //
  // Not awaited by anything on the write path. The rows are already in memory and already on
  // screen, and what this buys is only whether they are still there after a reload.
  static persistFrame(records, cursor) {
    return Durability.#write([ENTITIES, META], (transaction) => {
      const entities = transaction.objectStore(ENTITIES);
      const meta = transaction.objectStore(META);

      for (const record of records) {
        if (record.row === null) {
          entities.delete([record.type, record.id]);
        } else {
          entities.put(record);
        }
      }

      // A frame sent mid-fill names no place, because a client holding part of a pot could not
      // honour the claim one makes. The place already stored still describes the rows that were
      // there before this fill started, so it is left standing rather than cleared - which is what
      // lets a client cut off mid-fill come back asking for what it can still honour.
      if (cursor !== null) {
        meta.put(cursor, "cursor");
      }

      meta.put(Clock.last(), "clock");
    });
  }

  // The identity this browser presents, kept so that the next page load can ignore the fresh pair
  // it is offered and go on numbering where this one left off.
  static persistReplica(replica) {
    return Durability.#write([META], (transaction) => {
      transaction.objectStore(META).put(replica, "replica");
    });
  }

  // Takes up what the previous page load left, and answers the two things the runtime resumes
  // from: the place to greet the stream with, and the number to count batches on from.
  //
  // SYNCHRONOUS, and called after the page has mounted rather than before. After, because the rows
  // the page itself carried are the freshest thing this client has - the server rendered them for
  // this request - so they go in first and a stored row fills only what the page said nothing
  // about. Synchronous, because everything the mount leads to runs in one continuation, which is
  // what puts this ahead of the first local write without anything having to race.
  //
  // Answers NOTHING when there is nothing to take up - a browser with no durable storage, and
  // every call after the first. The second matters: the runtime's page-script listener runs again
  // on each client-side navigation, so this is reached once per page visit, and a later call that
  // answered a place of null would take away the one the stream had been keeping all along.
  //
  // The rows are dropped rather than used in three cases, and each is a case where showing them
  // would be showing something untrue. What this browser DID - its identity, its counter, its
  // clock - survives all three: those are not the server's to take away, and reusing a number or
  // restarting a clock low is how a write gets answered by the wrong batch or read as moved.
  static restore() {
    const loaded = Durability.#loaded;

    Durability.#loaded = null;

    if (loaded === null) {
      return null;
    }

    // Before anything else and whatever happens below: a stamp this browser issues has to be above
    // every stamp it issued or was told about on any earlier load.
    Clock.observe(loaded.clock);

    const ownerChanged =
      loaded.actorUserId !== (LocalDatabase.actorUserId ?? null);

    const refusal = Durability.#refusal(loaded, ownerChanged);

    if (refusal === null) {
      LocalDatabase.restore(loaded.records);
    } else {
      Logger.debug(
        `Hologram: the stored rows were dropped (${refusal}), this page fills from nothing`,
      );

      Durability.clear();
    }

    // A page load offers a fresh pair and a browser already holding one ignores it - re-minting per
    // load would abandon the numbering its batches are identified by. Somebody else signing in is
    // the one case where the held pair goes too: it was minted for the previous owner, or for a
    // session that is no longer theirs.
    if (loaded.replica !== null && !ownerChanged) {
      Replica.adopt(loaded.replica);
    } else {
      Durability.persistReplica(Replica.current());
    }

    Durability.#rememberOwner(loaded);

    return {cursor: refusal === null ? loaded.cursor : null, seq: loaded.seq};
  }

  // Drops the database entirely and puts this module back as it starts. For tests - nothing in the
  // framework throws away what a browser has kept.
  static async reset() {
    Durability.#close();

    try {
      await Durability.#request(
        globalThis.indexedDB.deleteDatabase(DATABASE_NAME),
      );
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.inFlight = 0;
  }

  static #close() {
    if (Durability.#db !== null) {
      Durability.#db.close();
      Durability.#db = null;
    }

    Durability.mode = "memory";
  }

  static #complete(transaction) {
    return new Promise((resolve, reject) => {
      transaction.onabort = () => reject(transaction.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  }

  // Something the database was asked to do could not be done. What follows is always the same:
  // what is stored goes, and this page carries on from memory.
  //
  // The rows go because a base missing one frame's is worse than no base at all - the next startup
  // cannot tell the two apart, and would resume from a place claiming rows that were never
  // written. What this browser DID is left alone, as everywhere else: a number reused and a clock
  // restarted low cost more than a re-download.
  //
  // The identity and its counter go too, and this is the ONE place they do. They survive a
  // resync, a model change and somebody else signing in because they stay TRUE through all three -
  // but a counter that has stopped advancing on disk while this page goes on spending numbers is
  // no longer true, and keeping it would cause the very thing it exists to prevent: the next load
  // would resume from it and hand out numbers the server has already answered, which it answers
  // again from the record of the batch that first carried them. The distinct writes would be
  // dropped in silence.
  //
  // Absent is safe where stale is not. A load that finds no identity takes the fresh pair its own
  // page was minted - a new id, with no record anywhere - and counts from nothing. The clock is
  // left, because it only ever moves forward and cannot go stale in this way.
  //
  // The wipe deliberately does NOT go through the ordinary write path. A failure here must not
  // come back round to this function, and it cannot: nothing in this block reports one. That is
  // also why there is no "already failing" flag to keep in step - the shape rules the case out
  // rather than catching it.
  static #fail(reason) {
    Logger.debug(
      `Hologram: durable storage stopped (${reason}), the database lives in memory for this page`,
    );

    try {
      const transaction = Durability.#db.transaction(
        [ENTITIES, META],
        "readwrite",
      );

      Durability.#wipe(transaction);

      const meta = transaction.objectStore(META);

      meta.delete("replica");
      meta.delete("seq");
    } catch {
      // There is nothing further to try - this page stops storing either way.
    }

    Durability.#close();
  }

  // Everything the previous page load left, in one read - the six things `meta` holds and every
  // row record. Absences are normalized here rather than at every reader: a key nothing was ever
  // written under reads as undefined, and "nothing stored" is a state restore has to reason about.
  static async #load() {
    const transaction = Durability.#db.transaction(
      [ENTITIES, META],
      "readonly",
    );

    const entities = transaction.objectStore(ENTITIES);
    const meta = transaction.objectStore(META);

    const [actorUserId, clock, cursor, modelHash, records, replica, seq] =
      await Promise.all([
        Durability.#request(meta.get("actorUserId")),
        Durability.#request(meta.get("clock")),
        Durability.#request(meta.get("cursor")),
        Durability.#request(meta.get("modelHash")),
        Durability.#request(entities.getAll()),
        Durability.#request(meta.get("replica")),
        Durability.#request(meta.get("seq")),
      ]);

    return {
      actorUserId: actorUserId ?? null,
      clock: clock ?? 0,
      cursor: cursor ?? null,
      modelHash: modelHash ?? null,
      records: records ?? [],
      replica: replica ?? null,
      seq: seq ?? 0,
    };
  }

  static #memoryMode(reason) {
    Logger.debug(
      `Hologram: no durable storage (${reason}), the database lives in memory for this page`,
    );

    Durability.#close();
  }

  // Why the stored rows cannot be used, or nothing when they can.
  //
  // No place is the sharpest of the three: rows were written by a fill that never finished, and a
  // base with no place is not resumable at all - the server would fill it from scratch and never
  // say which of the held rows it is no longer sending, so a row deleted while this browser was
  // away would stay on the screen for as long as the store lived.
  //
  // A model changed under them makes them unreadable by this bundle, and an owner changed makes
  // them somebody else's - and the second is not corrected by the stream either, since a resuming
  // client is told what MOVED, never what it should no longer be holding.
  static #refusal(loaded, ownerChanged) {
    if (loaded.cursor === null) {
      return "no place to resume from";
    }

    if (loaded.modelHash !== globalThis.Hologram.sync.modelHash) {
      return "the model changed";
    }

    if (ownerChanged) {
      return "somebody else is signed in";
    }

    return null;
  }

  // Who this page belongs to and what model it speaks, so the next load can ask both questions of
  // what it finds. Written only when one of them has moved, which is a page load in a new session
  // or the first after a deploy - never on the ordinary case.
  static #rememberOwner(loaded) {
    const actorUserId = LocalDatabase.actorUserId ?? null;
    const modelHash = globalThis.Hologram.sync.modelHash;

    if (loaded.actorUserId === actorUserId && loaded.modelHash === modelHash) {
      return;
    }

    Durability.#write([META], (transaction) => {
      const meta = transaction.objectStore(META);

      meta.put(actorUserId, "actorUserId");
      meta.put(modelHash, "modelHash");
    });
  }

  static #request(request) {
    return new Promise((resolve, reject) => {
      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);

      // Only an open can be blocked, and only by a tab still holding the database at a version
      // this one is trying to replace - which is not something to wait out. Set here rather than
      // beside the open, so that one wrapper covers every outcome a request has.
      request.onblocked = () => reject(new Error("blocked by another tab"));
    });
  }

  // Two stores, and the facts ride inside a row's record rather than in a third: they are keyed by
  // their source row, a row leaving takes them with it, and an edge names the row whose
  // relationships changed - so one row is one record and one change is one write.
  //
  // A record is keyed by its type and id together, which is how a frame's rows are named, and how
  // one type's rows are dropped without touching another's.
  static #upgrade(db) {
    db.createObjectStore(ENTITIES, {keyPath: ["type", "id"]});
    db.createObjectStore(META);
  }

  // What is stored ON BEHALF OF THE SERVER, gone: the rows and the place they are dated at. Shared
  // by the resync path, which means it deliberately, and by the failure path, which has no choice.
  static #wipe(transaction) {
    transaction.objectStore(ENTITIES).clear();
    transaction.objectStore(META).delete("cursor");
  }

  // Every write goes through here, so there is one place that counts what is in flight and one
  // place that decides what a failure means.
  //
  // `relaxed` durability lets the browser answer before the operating system has flushed, which is
  // the right trade for a cache of what the server already holds: throughput here is bound by
  // commits, and the worst a lost tail costs is rows downloaded again.
  //
  // In memory mode this answers an already-settled promise, so a caller that awaits one - the
  // batch counter does - waits for nothing rather than branching.
  static async #write(storeNames, fn) {
    if (Durability.mode === "memory") {
      return;
    }

    Durability.inFlight += 1;

    try {
      const transaction = Durability.#db.transaction(storeNames, "readwrite", {
        durability: "relaxed",
      });

      fn(transaction);

      await Durability.#complete(transaction);
    } catch (error) {
      Durability.#fail(`write failed (${error})`);
    } finally {
      Durability.inFlight -= 1;
    }
  }
}

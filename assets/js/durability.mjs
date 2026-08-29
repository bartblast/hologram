"use strict";

import Clock from "./clock.mjs";
import Logger from "./logger.mjs";

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
// identity, the batch counter and the clock - and those three outlive everything else here,
// including a resync, a model change and somebody else signing in. A number reused is a batch the
// server answers from the record of a different batch, and a clock restarted low is a write the
// server reads as moved.
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

  // Drops what the SERVER said and keeps what this browser did: the rows go, the place they were
  // dated at goes with them, and the identity, the counter and the clock stay. Called when a
  // resync replaces the whole pot, and when what is stored cannot be read by this page.
  static clear() {
    return Durability.#write([ENTITIES, META], (transaction) => {
      transaction.objectStore(ENTITIES).clear();
      transaction.objectStore(META).delete("cursor");
    });
  }

  // Answers nothing, and never throws: a browser that cannot store is a browser that carries on
  // from memory. Every way that can happen is named, because the reason is what a developer needs
  // when a page is unexpectedly re-downloading everything.
  static async open() {
    if (!globalThis.Hologram.sync) {
      return Durability.#memoryMode("no data model");
    }

    if (!globalThis.indexedDB) {
      return Durability.#memoryMode("IndexedDB unavailable");
    }

    const request = globalThis.indexedDB.open(DATABASE_NAME, VERSION);

    request.onupgradeneeded = () => Durability.#upgrade(request.result);

    try {
      Durability.#db = await Durability.#request(request);
    } catch (error) {
      return Durability.#memoryMode(`open failed (${error})`);
    }

    // Another tab is trying to move the database to a version this bundle does not speak, and
    // holding it open would block that tab indefinitely. Letting go costs this page its durability
    // and nothing else.
    Durability.#db.onversionchange = () => Durability.#fail("version change");

    Durability.mode = "indexeddb";
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
  // this page stops storing and carries on from memory, because a partial record is worse than
  // none - it cannot be told from a whole one at the next startup.
  static #fail(reason) {
    Logger.debug(
      `Hologram: durable storage stopped (${reason}), the database lives in memory for this page`,
    );

    Durability.#close();
  }

  static #memoryMode(reason) {
    Logger.debug(
      `Hologram: no durable storage (${reason}), the database lives in memory for this page`,
    );

    Durability.#close();
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

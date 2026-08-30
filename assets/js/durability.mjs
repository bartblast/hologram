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
// And it holds the QUEUE: the batches this browser has written and not yet had an answer to,
// which is the one thing here that is nobody else's copy of anything. A row can always be
// downloaded again; a write nothing has taken delivery of exists only where it was made. So the
// queue outlives more than the rest - a resync and somebody else signing in leave it alone, and
// even a storage failure keeps what is already on disk, because those batches are still the
// user's unfinished work whatever has gone wrong since. Its record shape is FROZEN, spelled and
// argued in `batch.mjs`: a bundle drains what an older bundle wrote.
//
// They do NOT outlive a storage failure, and that is the one exception. After one, this page goes
// on spending numbers that nothing records, so a stored counter is stale rather than merely old -
// and a later load resuming from it would hand out numbers already answered. Absent is safe where
// stale is not.
//
// ONE DATABASE PER MODEL VERSION, named for the layout of the store itself and the model this
// bundle speaks. A deploy that changes the model lands in a new tab while an old tab is still open,
// and the two would otherwise share one store - a v1 tab must never read rows v2 rewrote, and no
// lens code ships to the browser to translate them. Named apart, they cannot meet: every tab is
// durable the whole time, in its own bundle's shape, and nothing has to decide which of them
// yields. The price is one refill per model change, which is what a model change costs anyway.
// (Draining an old model's database and deleting it once its tabs are gone is version skew's to
// build - what this step owes is only that the two never share.)
//
// Where the browser offers no durable storage - private browsing, an odd embedder, a failed
// transaction - the whole thing degrades to memory mode: fully functional, and honest about it
// through `mode`.
const ENTITIES = "entities";

// The shape of the store: which object stores exist, keyed how. Part of the database's NAME, so a
// bundle with a different layout opens a different database rather than upgrading this one - which
// is why VERSION below never moves.
//
// Still 1 with the queue added to it: the shape is edited in place while nothing anywhere holds
// data in the old one, and the number starts moving when there is something to move it for. A
// browser that a person opened by hand before the queue existed holds a two-store database and
// drops to memory mode on the missing store - clearing site data is the whole of the fix, and
// nothing automated is in that position, since every driven browser starts from an empty profile.
const LAYOUT = 1;

const META = "meta";
const QUEUE = "queue";
const VERSION = 1;

export default class Durability {
  // Transactions started and not yet complete. A test waits on it, and a devtools panel reads it -
  // nothing in the framework does.
  static inFlight = 0;

  // "indexeddb" once a database is open, "memory" before that and after anything goes wrong.
  static mode = "memory";

  // How many batch records the open found, of every owner - not only the ones this page may take
  // up. Taken once and not kept current: a test and a devtools panel read it to tell "this page
  // is not sending them" apart from "there are none", and nothing in the framework reads it.
  static storedBatches = 0;

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

      const request = globalThis.indexedDB.open(
        Durability.#databaseName(),
        VERSION,
      );

      request.onupgradeneeded = () => Durability.#upgrade(request.result);

      Durability.#db = await Durability.#request(request);
    } catch (error) {
      return Durability.#memoryMode(`open failed (${error})`);
    }

    // Another tab is moving the database to a version this bundle does not speak. Letting go AT
    // ONCE is the whole of what the event asks for: holding on blocks that upgrade for as long as
    // this page lives, and even starting a transaction here would block it for as long as the
    // transaction takes.
    //
    // Closed rather than failed, and the difference matters: nothing stored has become untrue. The
    // rows, the place and the counter are all still exactly what they were, and the bundle doing
    // the upgrading is the one that decides what to carry across. Wiping would block the upgrade
    // in order to throw away a store that the upgrading bundle wanted.
    Durability.#db.onversionchange = () => {
      Logger.debug(
        "Hologram: another tab needs a new database version, the database lives in memory for this page",
      );

      Durability.#close();
    };

    Durability.mode = "indexeddb";

    try {
      Durability.#loaded = await Durability.#load();
      Durability.storedBatches = Durability.#loaded.queue.length;
    } catch (error) {
      return Durability.#memoryMode(`read failed (${error})`);
    }
  }

  // A batch this browser has sealed and the number it spent on it, written down as one fact.
  //
  // The ONE write anything waits for. A batch is identified by its replica and its number, and the
  // server answers a number it has already seen from its record rather than applying it again - so
  // a number handed out but never written down is a number the next page load hands out a second
  // time, and the batch carrying it is answered with what the FIRST batch got.
  //
  // The batch and its number go down TOGETHER, in one transaction, because either one without the
  // other is wrong in its own way. A number with no batch is what the counter alone bought: the
  // next load counts on from work that no longer exists anywhere. A batch with no number is worse
  // - the next load would count from below it and hand the same number to something else, and
  // whichever of the two reached the server second would be answered with the other's verdict.
  //
  // What a crash between sealing and committing costs is a batch that was never sent, which is the
  // cheap side of the trade and the only side left once the two are one write.
  static persistBatch(batch) {
    return Durability.#write([META, QUEUE], (transaction) => {
      transaction.objectStore(QUEUE).put(batch.record());

      const meta = transaction.objectStore(META);

      meta.put(batch.seq, "seq");
      meta.put(Clock.last(), "clock");
    });
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
  // The rows are dropped rather than used in two cases, and each is a case where showing them
  // would be showing something untrue. (A model change is not among them any more: a bundle on
  // another model opens another database, and finds it empty.) What this browser DID - its identity, its counter, its
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
        globalThis.indexedDB.deleteDatabase(Durability.#databaseName()),
      );
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.inFlight = 0;
    Durability.storedBatches = 0;
  }

  // `hologram.<layout>.<model hash>` - a bundle carrying another store layout, or speaking another
  // model, opens a database of its own. Null when the build has no data model, and so nothing to
  // name one for.
  //
  // The framework's half comes first and the app's second, broad before narrow: the layout is
  // Hologram's own and moves when the shape of the store does, the model hash is the app's and
  // moves on any deploy that touches an entity. That also leaves the stable half as a prefix -
  // `hologram.<layout>.` names every database of one shape, which is a prefix test rather than a
  // parse for anything that ever has to gate on a shape it cannot read.
  static #databaseName() {
    const modelHash = globalThis.Hologram.sync?.modelHash;

    return modelHash ? `hologram.${LAYOUT}.${modelHash}` : null;
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
      [ENTITIES, META, QUEUE],
      "readonly",
    );

    const entities = transaction.objectStore(ENTITIES);
    const meta = transaction.objectStore(META);
    const queue = transaction.objectStore(QUEUE);

    const [actorUserId, clock, cursor, queued, records, replica, seq] =
      await Promise.all([
        Durability.#request(meta.get("actorUserId")),
        Durability.#request(meta.get("clock")),
        Durability.#request(meta.get("cursor")),
        Durability.#request(queue.getAll()),
        Durability.#request(entities.getAll()),
        Durability.#request(meta.get("replica")),
        Durability.#request(meta.get("seq")),
      ]);

    return {
      actorUserId: actorUserId ?? null,
      clock: clock ?? 0,
      cursor: cursor ?? null,
      queue: queued ?? [],
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
  // No place is the sharper of the two: rows were written by a fill that never finished, and a
  // base with no place is not resumable at all - the server would fill it from scratch and never
  // say which of the held rows it is no longer sending, so a row deleted while this browser was
  // away would stay on the screen for as long as the store lived.
  //
  // An owner changed makes them somebody else's - and that is not corrected by the stream either,
  // since a resuming client is told what MOVED, never what it should no longer be holding.
  static #refusal(loaded, ownerChanged) {
    if (loaded.cursor === null) {
      return "no place to resume from";
    }

    if (ownerChanged) {
      return "somebody else is signed in";
    }

    return null;
  }

  // Who this page belongs to, so the next load can ask whether it still does. Written only when
  // that has moved - a page load in a new session - never on the ordinary case.
  static #rememberOwner(loaded) {
    const actorUserId = LocalDatabase.actorUserId ?? null;

    if (loaded.actorUserId === actorUserId) {
      return;
    }

    Durability.#write([META], (transaction) => {
      transaction.objectStore(META).put(actorUserId, "actorUserId");
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

  // The facts ride inside a row's record rather than in a store of their own: they are keyed by
  // their source row, a row leaving takes them with it, and an edge names the row whose
  // relationships changed - so one row is one record and one change is one write.
  //
  // A row record is keyed by its type and id together, which is how a frame's rows are named, and
  // how one type's rows are dropped without touching another's.
  //
  // A batch is keyed by its number, because that is the order batches were made in and therefore
  // the order they ship in - a later batch may name a row an earlier one created. Reading them
  // back in key order is reading them back in the order to send them, with nothing to sort.
  static #upgrade(db) {
    db.createObjectStore(ENTITIES, {keyPath: ["type", "id"]});
    db.createObjectStore(META);
    db.createObjectStore(QUEUE, {keyPath: "seq"});
  }

  // What is stored ON BEHALF OF THE SERVER, gone: the rows and the place they are dated at. Shared
  // by the resync path, which means it deliberately, and by the failure path, which has no choice.
  //
  // The queue is deliberately not touched by either. A batch waiting to go out is this browser's
  // own work rather than a copy of the server's, so neither the server replacing what it says nor
  // this page losing the ability to store anything further makes one untrue.
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

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

  // Whether the browser has agreed to keep this origin's storage rather than evicting it under
  // pressure, and nothing until it has been asked or where it cannot be. A devtools read; nothing
  // in the framework reads it.
  static persisted = null;

  // How many batch records the open found, of every owner - not only the ones this page may take
  // up. Taken once and not kept current: a test and a devtools panel read it to tell "this page
  // is not sending them" apart from "there are none", and nothing in the framework reads it.
  static storedBatches = 0;

  static #db = null;

  // What open() read, held until restore() consumes it. Read at open so that restore has nothing
  // to await: it runs after the page has mounted, and everything after the mount happens in one
  // continuation, before an action could dispatch and write.
  static #loaded = null;

  // Whether this page load has already put the question to the browser. Flipped BEFORE the asking
  // starts, which is what stops two batches stored in the same turn from both asking.
  static #persistenceAsked = false;

  // The batches this browser has filed above a number, oldest first - what a tab reads before it
  // sends, so that what it ships is the queue as the DATABASE holds it rather than as messages
  // happened to reach it.
  //
  // Why it is read at all: any tab of a group can file a batch, and it says so on the channel - but
  // a message can be missed by a tab that was starting up, and a tab that filed one and closed
  // before saying anything sends no message at all. The store is the record either way, and reading
  // it back is reading it in number order, which is the order batches must go out in.
  //
  // A READ, so it is deliberately not `#write`: it starts no read-write transaction, and it is not
  // counted as work in flight, which is what a test waits on to know a WRITE has landed. A read
  // that fails answers nothing rather than tearing the storage down - nothing has been lost, and
  // the next send asks again.
  static async batchesAbove(seq) {
    if (Durability.mode === "memory") {
      return [];
    }

    try {
      const transaction = Durability.#db.transaction([QUEUE], "readonly");

      const records = await Durability.#request(
        transaction
          .objectStore(QUEUE)
          .getAll(globalThis.IDBKeyRange.lowerBound(seq, true)),
      );

      return records ?? [];
    } catch {
      return [];
    }
  }

  // Drops what the SERVER said and keeps what this browser did: the rows go, the place they were
  // dated at goes with them, and the identity, the counter and the clock stay. Called when a
  // resync replaces the whole pot, and when what is stored cannot be read by this page.
  static clear() {
    return Durability.#write([ENTITIES, META], Durability.#wipe);
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
  //
  // Public because the group of tabs sharing this database is named from it, and so is the lock
  // that elects their leader - one database, one queue, one leader.
  static databaseName() {
    const modelHash = globalThis.Hologram.sync?.modelHash;

    return modelHash ? `hologram.${LAYOUT}.${modelHash}` : null;
  }

  // A batch this browser has sealed, given the next number and written down - all three inside ONE
  // TRANSACTION, which is what makes the number safe to share between tabs.
  //
  // The number is READ where it is spent. Every tab of a browser writes into one queue keyed by
  // that number, so a counter moved in a tab's own memory is a counter two tabs can move to the
  // same value - and the second `put` would then overwrite the first tab's batch, losing a write
  // with nothing said.
  //
  // WHAT MAKES THE READ AND THE WRITE ONE STEP IS THE TRANSACTION, and it is worth saying outright
  // because it is easy to read this as unguarded. IndexedDB orders read-write transactions whose
  // scopes overlap, and it orders them per DATABASE rather than per connection - so a second tab
  // asking for `meta` and `queue` waits until the first tab's transaction has committed, and then
  // reads the number that transaction wrote. A Web Lock around this was written and removed: it
  // guarded nothing this does not already guarantee, and every mutation of it stayed green.
  //
  // What that costs is testability, which is the price of the guarantee living in the database
  // rather than in this file: a fake IndexedDB serializes everything anyway, so no unit test here
  // can tell a correct version from one that reads the counter outside the transaction. The two
  // tabs of `multi_tab_test.exs` are what bind it, in a browser where the case is real.
  //
  // The number taken is above the counter AND above every batch already in the queue, which are
  // the same thing until a storage failure: that drops the counter (a page that goes on spending
  // numbers nothing records leaves a stale one) and keeps the queue (a stored batch is still the
  // user's unfinished work). 10b applied that rule when a page load resumed; applying it at every
  // seal is what makes it hold for a tab that never resumed anything.
  //
  // The batch and its number go down TOGETHER, in one transaction, because either without the
  // other is wrong in its own way. A number with no batch is one the next load counts on from for
  // work that no longer exists anywhere. A batch with no number is worse - the next load would
  // count from below it and hand the same number to something else, and whichever reached the
  // server second would be answered with the other's verdict.
  //
  // Nothing is read with `await` inside the transaction: an IndexedDB transaction commits the
  // moment it has no request outstanding, so the write has to be chained onto the read's own
  // callback rather than sequenced by the event loop.
  //
  // In memory mode the batch is left UNNUMBERED and the caller numbers it: there is nothing to file
  // and no transaction to order it against.
  static fileBatch(batch) {
    if (Durability.mode === "memory") {
      return Promise.resolve();
    }

    // The first batch stored is the first moment this browser holds something that exists nowhere
    // else - a row can always be downloaded again, an unsent write cannot - so it is the moment to
    // ask for the storage to be kept. Once per page load, and never awaited: the batch's own write
    // does not wait on a permission being read.
    if (!Durability.#persistenceAsked) {
      Durability.#persistenceAsked = true;

      Durability.#requestPersistence();
    }

    return Durability.#write([META, QUEUE], (transaction) => {
      const meta = transaction.objectStore(META);
      const queue = transaction.objectStore(QUEUE);
      const counter = meta.get("seq");

      counter.onsuccess = () => {
        const highest = queue.openKeyCursor(null, "prev");

        highest.onsuccess = () => {
          const spent = Math.max(counter.result ?? 0, highest.result?.key ?? 0);

          batch.seal(spent + 1);

          queue.put(batch.record());
          meta.put(batch.seq, "seq");
          meta.put(Clock.last(), "clock");
        };
      };
    });
  }

  // A batch the server has ruled on, gone from the queue. Confirmed or refused alike: either way
  // nothing is waiting on it any more, and a later page load has no reason to take it up.
  //
  // Fire and forget, unlike the write that put it there. What a crash between the verdict and this
  // delete costs is one batch sent a second time on the next load - and a second arrival of the
  // same replica and number is answered from the server's record of the first rather than applied
  // again, so the cost is a round trip rather than a duplicate write.
  static forgetBatch(seq) {
    return Durability.#write([QUEUE], (transaction) =>
      transaction.objectStore(QUEUE).delete(seq),
    );
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

      // What is stored is shared by every tab of this browser, and sharing it needs one tab to
      // speak for the rest - which is what a Web Lock elects. Without one, every tab leads itself:
      // two streams downloading every frame twice, and two senders draining ONE queue under one
      // replica identity, where the watermark a frame carries - the number that stops this client
      // applying its own write a second time - describes a single sender. So a browser that cannot
      // elect keeps its tabs independent, each working from its own memory: it costs durability
      // there, and it cannot cost a write.
      //
      // (The COUNTER is not the reason, though it reads like one: the number is read and spent
      // inside the transaction that files the batch, and IndexedDB orders those across tabs on its
      // own - see `fileBatch`.)
      if (!globalThis.navigator?.locks) {
        return Durability.#memoryMode("no Web Locks");
      }

      const request = globalThis.indexedDB.open(
        Durability.databaseName(),
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
  //
  // One number and one queue for the whole browser, not one per tab (10a's D1): a person has one
  // replica, and the log should read that way. Until the multi-tab work takes the number inside the
  // same lock that files the batch, two tabs writing at the same moment can spend one number - and
  // the second tab's write here overwrites the first tab's batch, which is the same known limit
  // with a sharper edge than it had when only a counter was stored.
  static persistBatch(batch) {
    // The first batch stored is the first moment this browser holds something that exists nowhere
    // else - a row can always be downloaded again, an unsent write cannot - so it is the moment to
    // ask for the storage to be kept. Once per page load, and never awaited: the batch's own write
    // does not wait on a permission being read.
    if (!Durability.#persistenceAsked) {
      Durability.#persistenceAsked = true;

      Durability.#requestPersistence();
    }

    return Durability.#write([META, QUEUE], (transaction) => {
      transaction.objectStore(QUEUE).put(batch.record());

      const meta = transaction.objectStore(META);

      meta.put(batch.seq, "seq");
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

  // A pending batch whose writes the base has caught up with, written down again for the marks.
  //
  // Why the marks are worth storing at all: a batch can be sent, committed, have its frame arrive
  // and be stored, and then lose its ANSWER to a dropped connection. The next page load takes the
  // batch up and sends it again, the server answers from its record, and the client promotes it -
  // and a moved counter promoted onto a base that already holds the move counts it twice, for
  // good. Nothing later corrects that, because the server has nothing new to say about a row
  // nobody has touched since. The marks are what makes the promotion pass over it.
  //
  // The counter is deliberately NOT rewritten here, which is what makes this different from the
  // write that first stored the batch. A frame can land the writes of a batch that is not the
  // newest one sealed, and putting this batch's number down would walk the counter backwards -
  // onto a number a later batch has already spent.
  //
  // Fire and forget: the marks are already in memory, and what storing them buys is only whether
  // they are still true after a reload.
  static persistLanded(batch) {
    return Durability.#write([QUEUE], (transaction) =>
      transaction.objectStore(QUEUE).put(batch.record()),
    );
  }

  // The identity this browser presents, kept so that the next page load can ignore the fresh pair
  // it is offered and go on numbering where this one left off.
  static persistReplica(replica) {
    return Durability.#write([META], (transaction) => {
      transaction.objectStore(META).put(replica, "replica");
    });
  }

  // Takes up what the previous page load left, and answers the three things the runtime resumes
  // from: the place to greet the stream with, the number to count batches on from, and the batches
  // this page may send.
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
  //
  // The batches are taken up whether or not the ROWS are, and the queue is not dropped in either
  // case. A pending write over a base that has started again is the same case as a resync with
  // writes pending: a create folds as a new row, an update of a row the base does not hold yet
  // folds nothing until the fill brings it, and the fill's rows carry the revisions the fold
  // weighs the write against.
  //
  // ONLY THIS PAGE'S OWN USER'S BATCHES. A batch is applied by the server under the user of the
  // session that SENDS it, so a batch taken up by a page somebody else has since signed in on
  // would be written in their name - or refused by their policies, and the work thrown away.
  // Somebody else's batches are left in the store untouched: not loaded, not folded, not sent, not
  // forgotten, and taken up by the next load that mounts under their own owner. (Nothing else can
  // deliver them - the server knows nothing of a batch it has never been sent - so waiting is the
  // whole of what is available, and it costs nothing.)
  //
  // The counter resumes above every STORED BATCH as well as above the number itself, which are
  // normally the same. They part after a storage failure: the counter is dropped there, because a
  // page that goes on spending numbers nothing records leaves a stale one behind - and the queue is
  // kept, because a batch already written down is still the user's unfinished work. Counting from
  // nothing would then hand a new batch a number a stored one already holds, and its record would
  // be overwritten by a batch that is not it. The maximum is what makes keeping one and dropping
  // the other safe.
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

    const owner = LocalDatabase.actorUserId ?? null;

    return {
      batches: loaded.queue.filter((record) => record.actorUserId === owner),
      cursor: refusal === null ? loaded.cursor : null,
      seq: Math.max(loaded.seq, ...loaded.queue.map((record) => record.seq)),
    };
  }

  // Drops the database entirely and puts this module back as it starts. For tests - nothing in the
  // framework throws away what a browser has kept.
  static async reset() {
    Durability.#close();

    try {
      await Durability.#request(
        globalThis.indexedDB.deleteDatabase(Durability.databaseName()),
      );
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.inFlight = 0;
    Durability.persisted = null;
    Durability.storedBatches = 0;

    Durability.#persistenceAsked = false;
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

  // Asks the browser to exempt this origin from eviction - and NEVER puts a dialog in front of
  // anyone to do it.
  //
  // Worth asking at all because of Safari: it clears a site's storage after about seven days
  // without a visit, and where that used to cost a re-download it now costs writes that were never
  // sent. Chrome and Firefox evict only under disk pressure, and Chrome grants this on its own to
  // a site somebody actually uses.
  //
  // The permission is READ before it is requested, which is the whole of how the dialog is avoided:
  // `prompt` means asking would raise one, so this does not ask. Not a browser check - there is no
  // honest way to write one, since every browser's user agent lies about what it is - but a
  // question put to the browser about its own behaviour.
  //
  // A browser that does not know the permission name throws, and that is the case to go AHEAD on:
  // it does not gate this behind a dialog, and Safari - which knows no such permission - is exactly
  // the browser the seven-day rule makes this worth doing for.
  //
  // The lever that beats all of this is INSTALLING the app, which is exempt from Safari's rule and
  // auto-granted by Chrome. Nothing here can ask for that, and it is where the mobile and desktop
  // story goes.
  static async #requestPersistence() {
    if (Durability.mode !== "indexeddb" || !navigator.storage?.persist) {
      return;
    }

    try {
      const {state} = await navigator.permissions.query({
        name: "persistent-storage",
      });

      if (state === "prompt") {
        Durability.persisted = false;

        Logger.debug(
          "Hologram: this browser would ask permission to keep the data, so it was not asked - storage here may be evicted",
        );

        return;
      }
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.persisted = await navigator.storage.persist();

    if (!Durability.persisted) {
      Logger.debug(
        "Hologram: the browser did not agree to keep this site's data, storage here may be evicted",
      );
    }
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

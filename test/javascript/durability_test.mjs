"use strict";

// A faithful IndexedDB rather than a stand-in of our own: what this module claims is that it
// drives the browser's database correctly, and only a real implementation of it can say so.
//
// The factory is imported and installed BY HAND rather than through the package's `auto` entry.
// That entry assigns to `window` wherever one exists, and under jsdom the window is not the global
// object the way it is in a browser - so `auto` would leave globalThis.indexedDB undefined, which
// is precisely the absence this module treats as "this browser cannot store". Imported by path
// like every dependency in this suite: node_modules lives under assets/, and a bare specifier
// resolves upward from the importing file, which never reaches it.
import fakeIndexedDB from "../../assets/node_modules/fake-indexeddb/build/esm/fakeIndexedDB.js";

// Installed beside the factory and for the same reason: a range is how a read names the part of a
// store it wants, and jsdom puts no IDBKeyRange on the global any more than it puts indexedDB there.
import FDBKeyRange from "../../assets/node_modules/fake-indexeddb/build/esm/FDBKeyRange.js";

// Its prototype is where a test makes a read fail: the module's own connection is private.
import FDBDatabase from "../../assets/node_modules/fake-indexeddb/build/esm/FDBDatabase.js";
import FDBObjectStore from "../../assets/node_modules/fake-indexeddb/build/esm/FDBObjectStore.js";

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import Durability from "../../assets/js/durability.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Model from "../../assets/js/model.mjs";
import Replica from "../../assets/js/replica.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

// registerWebApis puts sessionStorage on the global, which is where Logger writes - and every path
// through this module that gives up on storage says so through Logger.
defineRuntimeGlobals();
registerWebApis();

describe("Durability", () => {
  // Named for the store layout, and the protocol and the model the runtime globals below declare.
  const DATABASE_NAME = "hologram.1.7.model-a";

  // Installed for this suite and taken back down after it, never at module scope: mocha runs every
  // file in one process, and `open()` reads the absence of indexedDB as "this browser cannot
  // store" - so a factory left on the global would hand every later suite a working IndexedDB and
  // make its storage-mode answers depend on file order. Restored by deletion when it was absent,
  // so what comes after finds exactly what it would have found alone.
  let previousIndexedDB;
  let previousKeyRange;

  before(() => {
    previousIndexedDB = globalThis.indexedDB;
    previousKeyRange = globalThis.IDBKeyRange;

    globalThis.indexedDB = fakeIndexedDB;
    globalThis.IDBKeyRange = FDBKeyRange;
  });

  after(() => {
    if (previousIndexedDB === undefined) {
      delete globalThis.indexedDB;
    } else {
      globalThis.indexedDB = previousIndexedDB;
    }

    if (previousKeyRange === undefined) {
      delete globalThis.IDBKeyRange;
    } else {
      globalThis.IDBKeyRange = previousKeyRange;
    }
  });

  // Every connection this suite opens for itself, closed centrally below.
  let raw = [];

  beforeEach(async () => {
    globalThis.Hologram.sync = {modelHash: "model-a", protocolVersion: 7};

    Clock.reset();
    LocalDatabase.reset();
    Replica.reset();
    sessionStorage.clear();

    await Durability.reset();
  });

  // The handles are closed HERE rather than at the end of each test, because a test that fails
  // never reaches its own close - and an open connection blocks deleteDatabase, so the next red
  // test would hang instead of failing. A hang says nothing about what broke.
  afterEach(async () => {
    raw.forEach((db) => db.close());
    raw = [];

    await Durability.reset();
    await deleteEveryDatabase();

    Clock.reset();
    LocalDatabase.reset();

    // Left alone by LocalDatabase.reset() on purpose - a resync replaces what the server said and
    // does not change who is signed in - so the seed's owner has to be put back by hand, or it
    // reaches every suite that runs after this file.
    LocalDatabase.actorUserId = null;
    LocalDatabase.actorEntityId = null;

    Replica.reset();
    sinon.restore();

    delete globalThis.Hologram.sync;
  });

  // Every database this suite may have left, gone - `reset()` deletes only the one the current
  // model names, and a test that opens under another model leaves a second one behind.
  const deleteEveryDatabase = async () => {
    const databases = await globalThis.indexedDB.databases();

    for (const {name} of databases) {
      if (name.startsWith("hologram.")) {
        await new Promise((resolve) => {
          const request = globalThis.indexedDB.deleteDatabase(name);

          request.onsuccess = resolve;
          request.onerror = resolve;
        });
      }
    }
  };

  // Read back through a database of the test's own, never through the module under test - a module
  // trusted to read its own writes can agree with itself about a mistake in both directions.
  //
  // No version by default, which opens whatever is current: a reader that pinned one would fail
  // against a database another tab had already upgraded, which is precisely the state one of these
  // tests leaves behind. A version is passed only to FORCE an upgrade.
  const rawOpen = (version, name = DATABASE_NAME) =>
    new Promise((resolve, reject) => {
      const request =
        version === undefined
          ? globalThis.indexedDB.open(name)
          : globalThis.indexedDB.open(name, version);

      let upgraded = false;

      request.onupgradeneeded = () => (upgraded = true);
      request.onerror = () => reject(request.error);

      request.onsuccess = () => {
        raw.push(request.result);
        resolve({db: request.result, upgraded});
      };
    });

  const readAll = async (storeName, name = DATABASE_NAME) => {
    const {db} = await rawOpen(undefined, name);

    return new Promise((resolve, reject) => {
      const request = db.transaction(storeName).objectStore(storeName).getAll();

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);
    });
  };

  // Whether a promise has settled, without waiting on it: a settled one runs its callback in the
  // next microtask, and a store write does not complete before the next task.
  const isSettled = async (promise) => {
    let settled = false;

    promise.then(() => (settled = true));

    await Promise.resolve();
    await Promise.resolve();

    return settled;
  };

  const readMeta = async (key) => {
    const {db} = await rawOpen();

    return new Promise((resolve, reject) => {
      const request = db.transaction("meta").objectStore("meta").get(key);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);
    });
  };

  // The pair stored for the given user, by default the one this page is mounted for.
  const readPair = async (owner = LocalDatabase.actorUserId ?? null) =>
    readMeta(`replica:${owner ?? "anonymous"}`);

  const writeMeta = async (entries) => {
    const {db} = await rawOpen();

    return new Promise((resolve, reject) => {
      const transaction = db.transaction("meta", "readwrite");
      const meta = transaction.objectStore("meta");

      for (const [key, value] of Object.entries(entries)) {
        meta.put(value, key);
      }

      transaction.onerror = () => reject(transaction.error);
      transaction.oncomplete = () => resolve();
    });
  };

  const taskRecord = (id, title) => ({
    facts: {tags: []},
    id,
    row: {id, title},
    type: "MyApp.Task",
  });

  const sealedBatch = (seq, actorUserId = "u1") => {
    const batch = new Batch(null);

    batch.actorUserId = actorUserId;
    batch.append({id: "t1", op: "delete", type: "MyApp.Task"});
    batch.seal(seq);

    return batch;
  };

  // Through a real batch rather than a literal of its own, so a seed writes exactly what the
  // module writes and the two cannot drift apart.
  const batchRecord = (seq, actorUserId = "u1") =>
    sealedBatch(seq, actorUserId).record();

  // A batch as filing leaves it: its record in the queue, and its number and the clock in meta.
  const storeBatch = async (seq, actorUserId = "u1") => {
    await writeBatches([batchRecord(seq, actorUserId)]);
    await writeMeta({clock: Clock.last(), seq});
  };

  // Unsealed, because filing is what gives a batch its number.
  const unfiledBatch = (actorUserId = "u1") => {
    const batch = new Batch(null);

    batch.actorUserId = actorUserId;
    batch.append({id: "t1", op: "delete", type: "MyApp.Task"});

    return batch;
  };

  const writeBatches = async (records) => {
    const {db} = await rawOpen();

    return new Promise((resolve, reject) => {
      const transaction = db.transaction("queue", "readwrite");
      const queue = transaction.objectStore("queue");

      records.forEach((record) => queue.put(record));

      transaction.onerror = () => reject(transaction.error);
      transaction.oncomplete = () => resolve();
    });
  };

  const writeRecords = async (records) => {
    const {db} = await rawOpen();

    return new Promise((resolve, reject) => {
      const transaction = db.transaction("entities", "readwrite");
      const entities = transaction.objectStore("entities");

      records.forEach((record) => entities.put(record));

      transaction.onerror = () => reject(transaction.error);
      transaction.oncomplete = () => resolve();
    });
  };

  // The seed writes before this page has opened the adapter, so it creates the schema itself.
  // Deliberately NOT folded into rawOpen, which has to stay dumb: a reader that created stores
  // would let the open() test pass against an upgrade that created none.
  const createSchema = () =>
    new Promise((resolve, reject) => {
      const request = globalThis.indexedDB.open(DATABASE_NAME, 1);

      request.onupgradeneeded = () => {
        const db = request.result;

        db.createObjectStore("entities", {keyPath: ["type", "id"]});
        db.createObjectStore("meta");
        db.createObjectStore("queue", {keyPath: "seq"});
      };

      request.onerror = () => reject(request.error);

      request.onsuccess = () => {
        raw.push(request.result);
        resolve();
      };
    });

  // What a browser looks like one page load in: rows, the place they are dated at, the identity it
  // was minted, the number it counted to and where its clock stood.
  const seedPreviousLoad = async (overrides = {}) => {
    await createSchema();
    await writeRecords([taskRecord("t1", "Draft copy")]);

    const {replica, ...meta} = {
      actorUserId: "u1",
      clock: 1_756_100_000_123_004,
      cursor: "place-1",
      replica: {id: "r-stored", token: "statement-stored"},
      seq: 41,
      ...overrides,
    };

    await writeMeta(
      replica
        ? {
            ...meta,
            [`replica:${meta.actorUserId ?? "anonymous"}`]: replica,
          }
        : meta,
    );

    LocalDatabase.actorUserId = "u1";
    Replica.offer({id: "r-fresh", token: "statement-fresh"});
  };

  describe("batchesAbove()", () => {
    it("answers the records above the number, oldest first", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(9), batchRecord(2), batchRecord(5)]);

      assert.deepStrictEqual(await Durability.batchesAbove(2), [
        batchRecord(5),
        batchRecord(9),
      ]);
    });

    it("answers nothing for a number nothing was filed above", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(2), batchRecord(5)]);

      assert.deepStrictEqual(await Durability.batchesAbove(5), []);
    });

    it("answers nothing in memory mode", async () => {
      assert.deepStrictEqual(await Durability.batchesAbove(0), []);
      assert.equal(Durability.mode, "memory");
    });

    // A read that cannot be answered has lost nothing - the batches are still filed, and the next
    // send asks again - so it does not take the storage down the way a failed WRITE does.
    it("answers nothing when the store cannot be read, and goes on storing", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(2)]);

      const range = globalThis.IDBKeyRange;

      try {
        globalThis.IDBKeyRange = undefined;

        assert.deepStrictEqual(await Durability.batchesAbove(0), []);
      } finally {
        globalThis.IDBKeyRange = range;
      }

      assert.equal(Durability.mode, "indexeddb");
    });
  });

  describe("clear()", () => {
    it("drops the rows and the place, and keeps what this browser did", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      await writeMeta({
        actorUserId: "u1",
        "replica:u1": {id: "r1", token: "statement"},
        seq: 41,
      });

      LocalDatabase.actorUserId = "u1";

      await Durability.clear();

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));

      assert.equal(await readMeta("actorUserId"), "u1");
      assert.equal(await readMeta("seq"), 41);

      assert.deepStrictEqual(await readPair("u1"), {
        id: "r1",
        token: "statement",
      });
    });

    // A batch waiting to go out is this browser's own work rather than a copy of anything the
    // server holds, so the server replacing everything it says leaves it where it was.
    it("keeps the stored batches", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(1)]);

      await Durability.clear();

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [1],
      );
    });
  });

  // A row carrying something the browser cannot copy into its own storage. Real rather than
  // stubbed: what reaches this store is JSON the wire spelled, so a value like this is a bug in
  // the framework - and what the store does about one is what these tests are for.
  const unstorableRecord = () => ({
    facts: {},
    id: "t9",
    row: {id: "t9", title: () => "not JSON"},
    type: "MyApp.Task",
  });

  describe("a write that fails", () => {
    it("drops the rows and the place, and stops storing for this page", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      await Durability.persistFrame([unstorableRecord()], "place-2");

      assert.equal(Durability.mode, "memory");
      assert.include(Logger.getLogs(), "durable storage stopped");
      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));
    });

    // A stored counter exists only so that a later load does not reuse a number. Once storing has
    // stopped, this page goes on spending numbers that nothing records - so the stored one is
    // stale, and a load resuming from it would hand out numbers the server answers from the record
    // of the batch that first carried them, dropping the new writes in silence. Absent is safe
    // where stale is not: a load finding no identity takes its own page's fresh pair and counts
    // from nothing.
    // The rows and the place are gone for the whole browser, not for this tab - so a tab that goes
    // on writing frames into it would be dating rows the store no longer holds.
    it("tells the group it has stopped storing", async () => {
      const posting = sinon.stub(Tabs, "post");

      await Durability.open();
      await Durability.load();
      await Durability.persistFrame([unstorableRecord()], "place-2");

      sinon.assert.calledOnceWithExactly(posting, {kind: "storage_failed"});
    });

    // The log line goes to session storage, whose own quota the log can fill. Thrown, it would
    // reject the identity write every send waits on, and leave the store open and unwiped.
    it("stops storing even when the failure cannot be logged", async () => {
      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      sinon
        .stub(Logger, "debug")
        .throws(new DOMException("full", "QuotaExceededError"));

      // A pair the store cannot hold, so the write fails.
      Durability.persistReplica({id: () => {}, token: "statement"});

      await Durability.replicaWritten();

      assert.equal(Durability.mode, "memory");
      sinon.assert.calledOnceWithExactly(posting, {kind: "storage_failed"});

      assert.isUndefined(await readMeta("cursor"));
      assert.isUndefined(await readPair());
    });

    it("drops this user's identity, which has stopped being true", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(41);
      await Durability.persistReplica({id: "r1", token: "statement"});

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");
      assert.isUndefined(await readPair());
    });

    // Other users' pairs go on counting from it, so dropped it would hand them numbers they spent.
    // A full disk can refuse a write, and refused inside this transaction it would roll back the
    // wipe, leaving a place and a pair this page has stopped recording numbers under.
    it("drops the pair without writing anything", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);
      await Durability.replicaWritten();

      const putting = sinon.spy(FDBObjectStore.prototype, "put");

      await Durability.persistFrame([unstorableRecord()], "place-1");

      const wrotePair = putting
        .getCalls()
        .some(({args: [, key]}) => String(key).startsWith("replica:"));

      assert.isFalse(wrotePair);
      assert.isUndefined(await readPair("u1"));
    });

    // The pair whose numbers stopped being recorded is the document's, whoever the page is now.
    it("drops the pair of the user it was taken up for", async () => {
      await seedPreviousLoad();
      await writeMeta({"replica:u2": {id: "r-u2", token: "statement-u2"}});
      await Durability.open();
      await Durability.load();

      Durability.restore(true);
      await Durability.replicaWritten();

      LocalDatabase.actorUserId = "u2";

      // A pair the store cannot hold, so the write fails.
      Durability.persistReplica({id: () => {}, token: "statement"});

      await Durability.replicaWritten();

      assert.equal(Durability.mode, "memory");
      assert.isUndefined(await readPair("u1"));
      assert.equal((await readPair("u2")).id, "r-u2");
    });

    // The tab followed the session to u2 while u1's write was out, and u2's pair is what u2's
    // group goes on sending under.
    it("drops the pair of the user whose write failed, not the one the tab moved to", async () => {
      await seedPreviousLoad();
      await writeMeta({"replica:u2": {id: "r-u2", token: "statement-u2"}});
      await Durability.open();
      await Durability.load();

      Durability.restore(true);
      await Durability.replicaWritten();

      const opening = sinon.spy(FDBDatabase.prototype, "transaction");

      Durability.persistReplica({id: "r-u1-next", token: "statement-u1"});

      const transaction = opening.lastCall.returnValue;

      Replica.owner = "u2";
      transaction.abort();

      await Durability.replicaWritten();

      assert.equal(Durability.mode, "memory");
      assert.isUndefined(await readPair("u1"));
      assert.equal((await readPair("u2")).id, "r-u2");
    });

    it("keeps the counter", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(41);

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");
      assert.equal(await readMeta("seq"), 41);
    });

    it("keeps another user's identity", async () => {
      const pair = {id: "r-other", token: "statement-other"};

      await Durability.open();
      await Durability.load();
      await writeMeta({"replica:u9": pair});

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.deepStrictEqual(await readPair("u9"), pair);
    });

    // It only ever moves forward, so it cannot go stale the way the counter does - and a clock
    // restarted low writes revisions the server reads as moved.
    it("keeps the clock", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(41);

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");
      assert.isNumber(await readMeta("clock"));
    });

    it("leaves nothing in flight", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.inFlight, 0);
    });

    // Unlike the counter, a stored batch cannot go stale through this page carrying on: nothing
    // has answered it, and nothing will while there is nowhere to send it. It is the user's
    // unfinished work, and a later page load is the only thing that can still deliver it.
    it("keeps the stored batches", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(1)]);

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [1],
      );
    });
  });

  describe("detach()", () => {
    it("closes the database and keeps everything stored", async () => {
      await seedPreviousLoad();
      await writeBatches([batchRecord(7)]);
      await Durability.open();
      await Durability.load();

      Durability.detach();

      assert.equal(Durability.mode, "memory");
      assert.equal((await readAll("entities")).length, 1);
      assert.equal((await readAll("queue")).length, 1);
      assert.equal(await readMeta("cursor"), "place-1");
      assert.equal(await readMeta("seq"), 41);
      assert.notInclude(Logger.getLogs() ?? "", "durable storage stopped");
    });
  });

  describe("forgetBatch()", () => {
    it("deletes the record of the given number and no other", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(7);
      await storeBatch(8);

      await Durability.forgetBatch(7);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [8],
      );
    });

    it("does nothing in memory mode", async () => {
      await Durability.forgetBatch(7);

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
      assert.notInclude(Logger.getLogs() ?? "", "durable storage stopped");
    });
  });

  describe("open()", () => {
    // A bundle carrying another store layout, speaking another protocol or on another model, must
    // open a database of its own - which is what stops two tabs on different versions from ever
    // sharing one, or a group.
    it("names the database for the layout of the store, the protocol and the model it speaks", async () => {
      await Durability.open();

      const names = (await globalThis.indexedDB.databases()).map(
        (db) => db.name,
      );

      assert.include(names, DATABASE_NAME);
    });

    it("opens in indexeddb mode and creates the three object stores", async () => {
      await Durability.open();

      assert.equal(Durability.mode, "indexeddb");

      const {db} = await rawOpen();

      assert.deepStrictEqual(Array.from(db.objectStoreNames), [
        "entities",
        "meta",
        "queue",
      ]);

      db.close();
    });

    it("keys a row record by its type and id together", async () => {
      await Durability.open();

      const {db} = await rawOpen();

      assert.deepStrictEqual(
        db.transaction("entities").objectStore("entities").keyPath,
        ["type", "id"],
      );

      db.close();
    });

    // Keyed by its number rather than out of line, which is what makes reading the queue back a
    // read in the order the batches ship - a later batch may name a row an earlier one created,
    // and its based_on for a column an earlier one wrote is that batch's own stamp.
    it("keys a batch record by its number, so they read back in the order they ship", async () => {
      await Durability.open();

      await writeBatches([batchRecord(9), batchRecord(2)]);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [2, 9],
      );
    });

    it("stays in memory mode when the browser has no IndexedDB", async () => {
      const indexedDB = globalThis.indexedDB;

      try {
        delete globalThis.indexedDB;

        await Durability.open();

        assert.equal(Durability.mode, "memory");
      } finally {
        globalThis.indexedDB = indexedDB;
      }
    });

    // A store shared by tabs needs one of them to speak for the rest, and the lock is what elects
    // it. Without one, every tab streams and sends on its own under one identity - so a browser
    // that cannot elect keeps its tabs independent instead, each from its own memory.
    it("stays in memory mode when the browser has no Web Locks", async () => {
      const navigator = Object.getOwnPropertyDescriptor(
        globalThis,
        "navigator",
      );

      try {
        Object.defineProperty(globalThis, "navigator", {
          configurable: true,
          value: {},
        });

        await Durability.open();

        assert.equal(Durability.mode, "memory");

        assert.include(Logger.getLogs(), "no durable storage (no Web Locks)");
      } finally {
        Object.defineProperty(globalThis, "navigator", navigator);
      }
    });

    // A database another tab already moved past this bundle's version cannot be opened by it at
    // all - which is the shape every open failure has from here: no store, and a page that carries
    // on without one.
    it("stays in memory mode when opening fails", async () => {
      const {db} = await rawOpen(2);
      db.close();

      await Durability.open();

      assert.equal(Durability.mode, "memory");
    });

    // Storage that is present but refuses to be REACHED: a sandboxed iframe, an opaque origin, a
    // browser told to block site data. Both the property read and the open() call throw
    // synchronously there, and the runtime awaits this during boot - so a throw escaping would
    // fail the whole page, not merely leave it without a store.
    it("stays in memory mode when reaching IndexedDB throws", async () => {
      const indexedDB = globalThis.indexedDB;

      try {
        globalThis.indexedDB = {
          open: () => {
            throw new DOMException(
              "The operation is insecure.",
              "SecurityError",
            );
          },
        };

        await Durability.open();

        assert.equal(Durability.mode, "memory");
      } finally {
        globalThis.indexedDB = indexedDB;
      }
    });

    // Holding it open would block that tab for as long as this page lives, and the durability this
    // page gives up is one page's worth.
    // Nothing stored has become untrue, and the bundle doing the upgrading decides what to carry
    // across - so this lets go without taking anything with it. Wiping would also block the very
    // upgrade the event exists to get out of the way of.
    // Seeded through the module's own connection rather than a raw one: a raw connection stays
    // open for the rest of the test, and an upgrade cannot start while anything else holds the
    // database - the very thing this test is here to drive.
    it("lets the database go when another tab needs a new version", async () => {
      await Durability.open();
      await Durability.fileBatch(unfiledBatch());
      await Durability.persistReplica({id: "r1", token: "statement"});
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      const {db} = await rawOpen(2);

      assert.equal(Durability.mode, "memory");

      db.close();

      assert.equal(await readMeta("seq"), 1);
      assert.equal(await readMeta("cursor"), "place-1");
      assert.equal((await readAll("entities")).length, 1);

      assert.deepStrictEqual(await readPair(), {
        id: "r1",
        token: "statement",
      });
    });
  });

  describe("groupName()", () => {
    it("names a visitor's group", () => {
      assert.equal(Durability.groupName(null), `${DATABASE_NAME}.anonymous`);
    });

    it("names a user's group with the server's text for them", () => {
      assert.equal(Durability.groupName("i7"), `${DATABASE_NAME}.i7`);
    });

    it("keeps a user whose id is the word anonymous out of the visitors' group", () => {
      assert.notEqual(
        Durability.groupName("sanonymous"),
        Durability.groupName(null),
      );
    });
  });

  describe("load()", () => {
    it("counts the stored batches", async () => {
      await createSchema();
      await writeBatches([batchRecord(1), batchRecord(2)]);

      await Durability.open();

      assert.equal(Durability.storedBatches, 0);

      await Durability.load();

      assert.equal(Durability.storedBatches, 2);
    });

    // The tab joins its group between the two, so what the store holds is read only once it is
    // listening (see DataLayer.boot).
    it("reads nothing until asked", async () => {
      await seedPreviousLoad();
      await Durability.open();

      assert.isNull(Durability.restore(true));

      await Durability.load();

      assert.equal(Durability.restore(true).cursor, "place-1");
    });

    it("does nothing in memory mode", async () => {
      await seedPreviousLoad();
      await Durability.load();

      assert.equal(Durability.mode, "memory");
      assert.isNull(Durability.restore(true));
      assert.notInclude(Logger.getLogs() ?? "", "read failed");
    });

    it("stays in memory mode when the read fails", async () => {
      await seedPreviousLoad();
      await Durability.open();

      sinon
        .stub(FDBDatabase.prototype, "transaction")
        .throws(new DOMException("The read was refused.", "UnknownError"));

      await Durability.load();

      assert.equal(Durability.mode, "memory");
      assert.isNull(Durability.restore(true));
      assert.include(Logger.getLogs(), "no durable storage (read failed");
    });

    // A store let go while it was read - another tab could not write, or needs a new version -
    // leaves this tab leading itself, and the stored identity and queue are the group leader's.
    it("keeps nothing it read once the store was let go meanwhile", async () => {
      await seedPreviousLoad();
      await Durability.open();

      const loading = Durability.load();

      Durability.detach();

      await loading;

      assert.equal(Durability.mode, "memory");
      assert.isNull(Durability.restore(true));
    });

    // Another tab moving the database on makes nothing stored untrue, and this tab stays in its
    // group - so what it read is taken up as it would have been.
    it("keeps what it read when the database closes for a new version before the restore", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      // The seed's own connections would block the upgrade.
      raw.forEach((connection) => connection.close());

      const {db} = await rawOpen(2);

      db.close();

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.restore(true).cursor, "place-1");
    });

    // The group ends with a store failure another tab reported, and a follower that took a fresh
    // identity and let its batches go would take both back.
    it("keeps nothing it read once the store was let go before the restore", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.detach();

      assert.isNull(Durability.restore(true));
    });

    // A tab that moved to another group while this read ran loads again for that group, and what
    // this read found would be taken up as that group's.
    it("keeps nothing it read once the read stopped being current", async () => {
      await seedPreviousLoad();
      await Durability.open();

      let current = true;

      const loading = Durability.load(() => current);

      current = false;

      await loading;

      assert.equal(Durability.mode, "indexeddb");
      assert.isNull(Durability.restore(true));
    });
  });

  describe("asking the browser to keep the data", () => {
    let persistStub, previousNavigator;

    // Neither exists under jsdom, so both are installed here and taken back down after - a stub
    // left on the global would answer for every suite that runs later in this process.
    const equipBrowser = (state) => {
      persistStub = sinon.stub().resolves(true);

      navigator.storage = {persist: persistStub};

      navigator.permissions = {
        query:
          state === null
            ? sinon.stub().rejects(new TypeError("unknown permission"))
            : sinon.stub().resolves({state}),
      };
    };

    beforeEach(() => {
      previousNavigator = {
        permissions: navigator.permissions,
        storage: navigator.storage,
      };
    });

    afterEach(() => {
      navigator.permissions = previousNavigator.permissions;
      navigator.storage = previousNavigator.storage;
    });

    it("asks the browser to keep the data the first time a batch is stored", async () => {
      equipBrowser("granted");

      await Durability.open();
      await Durability.load();
      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.isTrue(persistStub.calledOnce);
      assert.isTrue(Durability.persisted);
    });

    it("asks once, however many batches are stored", async () => {
      equipBrowser("granted");

      await Durability.open();
      await Durability.load();
      await Durability.fileBatch(unfiledBatch());
      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.isTrue(persistStub.calledOnce);
    });

    // The whole of how a dialog is avoided: the permission is READ first, and `prompt` means
    // asking would raise one.
    it("does not ask where the browser would put a dialog in front of the user", async () => {
      equipBrowser("prompt");

      await Durability.open();
      await Durability.load();
      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.isFalse(persistStub.called);
      assert.isFalse(Durability.persisted);
    });

    // Safari knows no such permission and never prompts - and its seven-day eviction is what makes
    // this worth doing at all, so an unknown permission is the case to go ahead on.
    it("asks where the browser does not know the permission", async () => {
      equipBrowser(null);

      await Durability.open();
      await Durability.load();
      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.isTrue(persistStub.calledOnce);
    });

    it("records a refusal", async () => {
      equipBrowser("denied");
      persistStub.resolves(false);

      await Durability.open();
      await Durability.load();
      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.isFalse(Durability.persisted);
      assert.include(Logger.getLogs(), "did not agree to keep");
    });

    it("asks nothing in memory mode", async () => {
      equipBrowser("granted");

      await Durability.fileBatch(unfiledBatch());
      await waitForEventLoop();

      assert.equal(Durability.mode, "memory");
      assert.isFalse(persistStub.called);
      assert.isNull(Durability.persisted);
    });
  });

  describe("fileBatch()", () => {
    it("writes the batch, its number and the clock together", async () => {
      await Durability.open();
      await Durability.load();

      Clock.observe(1_756_100_000_123_004);

      const batch = unfiledBatch();

      await Durability.fileBatch(batch);

      assert.equal(batch.seq, 1);
      assert.deepStrictEqual(await readAll("queue"), [batchRecord(1)]);
      assert.equal(await readMeta("seq"), 1);
      assert.equal(await readMeta("clock"), 1_756_100_000_123_004);
    });

    // The sender waits on this one write before a batch goes out, so what it answers has to stay
    // pending until the batch is DOWN - not merely until it has been asked for. Nothing in flight
    // at the moment it settles is what says so, and one thing in flight before that is what says
    // the batch and its number went in a single transaction rather than two.
    it("answers a promise that settles once the batch is stored", async () => {
      await Durability.open();
      await Durability.load();

      const batch = unfiledBatch();
      const filing = Durability.fileBatch(batch);

      assert.equal(Durability.inFlight, 1);

      await filing;

      assert.equal(Durability.inFlight, 0);
      assert.deepStrictEqual(await readAll("queue"), [batch.record()]);
    });

    // What tells a batch the store holds from one that exists only in its tab.
    describe("whether it was stored", () => {
      it("answers so once the batch is down", async () => {
        await Durability.open();
        await Durability.load();

        assert.isTrue(await Durability.fileBatch(unfiledBatch()));
      });

      it("answers not when the write failed", async () => {
        await Durability.open();
        await Durability.load();

        const opening = sinon.spy(FDBDatabase.prototype, "transaction");
        const filing = Durability.fileBatch(unfiledBatch());

        opening.lastCall.returnValue.abort();

        assert.isFalse(await filing);
        assert.deepStrictEqual(await readAll("queue"), []);
      });

      it("answers not with nowhere to file it", async () => {
        assert.isFalse(await Durability.fileBatch(unfiledBatch()));
      });
    });

    it("numbers the batch above the stored counter", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(4);

      const batch = unfiledBatch();

      await Durability.fileBatch(batch);

      assert.equal(batch.seq, 5);
      assert.equal(await readMeta("seq"), 5);
    });

    // The ordinary state of a browser that has been using the app: every batch was answered and
    // dropped from the queue, and the counter is the only thing that remembers what has been spent.
    // Numbering from the queue alone would start again at 1, on numbers the server has already
    // answered - so it would answer the new batch from the record of an old one.
    it("numbers the batch above the counter when the queue is empty", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(9);
      await Durability.forgetBatch(9);

      const batch = unfiledBatch();

      await Durability.fileBatch(batch);

      assert.deepStrictEqual(await readAll("queue"), [batch.record()]);
      assert.equal(batch.seq, 10);
    });

    // The two part after a storage failure, which drops the counter and keeps the queue - and
    // counting from below a stored batch would hand its number to something else, whose record
    // would then overwrite it.
    it("numbers the batch above every stored batch when the counter was dropped", async () => {
      await Durability.open();
      await Durability.load();
      await writeBatches([batchRecord(7)]);

      const batch = unfiledBatch();

      await Durability.fileBatch(batch);

      assert.equal(batch.seq, 8);
      assert.equal(await readMeta("seq"), 8);
    });

    // Two tabs filing at the same moment is the case this exists for: the lock is what makes the
    // second read the first one's number rather than the number they both started from.
    it("numbers two batches filed at once apart", async () => {
      await Durability.open();
      await Durability.load();

      const first = unfiledBatch();
      const second = unfiledBatch();

      await Promise.all([
        Durability.fileBatch(first),
        Durability.fileBatch(second),
      ]);

      assert.sameMembers([first.seq, second.seq], [1, 2]);

      assert.sameMembers(
        (await readAll("queue")).map((record) => record.seq),
        [1, 2],
      );
    });

    it("leaves the batch unnumbered in memory mode", async () => {
      const batch = unfiledBatch();

      await Durability.fileBatch(batch);

      assert.isNull(batch.seq);
      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
    });
  });

  describe("persistFrame()", () => {
    it("puts a held row's record and deletes a gone row's", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy"), taskRecord("t2", "Ship it")],
        "place-1",
      );

      await Durability.persistFrame(
        [{id: "t1", row: null, type: "MyApp.Task"}],
        "place-2",
      );

      assert.deepStrictEqual(await readAll("entities"), [
        taskRecord("t2", "Ship it"),
      ]);
    });

    // The rows and the place go together, which is what stops a client naming a place it does not
    // hold the rows for - it would be told only what changed since, and the rows it never wrote
    // would be missing for good.
    it("writes a frame's rows and the place they are dated at", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      assert.deepStrictEqual(await readAll("entities"), [
        taskRecord("t1", "Draft copy"),
      ]);

      assert.equal(await readMeta("cursor"), "place-1");
    });

    // Mid-fill the server names no place, and the one already stored still describes the rows that
    // were there before the fill started.
    it("leaves the stored place alone for a frame naming none", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame([], "place-1");
      await Durability.persistFrame([], null);

      assert.equal(await readMeta("cursor"), "place-1");
    });

    it("writes where the clock stands", async () => {
      await Durability.open();
      await Durability.load();

      Clock.observe(1_756_100_000_123_004);

      await Durability.persistFrame([], "place-1");

      assert.equal(await readMeta("clock"), 1_756_100_000_123_004);
    });

    it("counts a transaction in flight until it completes", async () => {
      await Durability.open();
      await Durability.load();

      const writing = Durability.persistFrame([taskRecord("t1", "Draft")], "p");

      assert.equal(Durability.inFlight, 1);

      await writing;

      assert.equal(Durability.inFlight, 0);
    });

    // Silently, which is the part worth asserting: without the check the write is attempted
    // against a database that is not there, and a page with no storage would report a failure for
    // every frame it received.
    it("does nothing in memory mode", async () => {
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
      assert.notInclude(Logger.getLogs() ?? "", "durable storage stopped");
    });
  });

  describe("big integers", () => {
    const COUNTED = "MyApp.Counted";

    beforeEach(() => {
      globalThis.Hologram.sync.model = {
        [COUNTED]: {
          attributes: {id: "uuid", n: "integer"},
          relationships: {},
          serverOnly: [],
        },
      };

      Model.reset();
    });

    afterEach(() => {
      Model.reset();
    });

    it("brings a row's big integer back as the BigInt it was filed as", async () => {
      await Durability.open();
      await Durability.load();

      Deltas.apply({
        put_entity: {[COUNTED]: [{id: "c1", n: "9007199254740993"}]},
      });

      await Durability.persistFrame(
        [
          {
            facts: {},
            id: "c1",
            row: LocalDatabase.baseRow(COUNTED, "c1"),
            type: COUNTED,
          },
        ],
        "place-1",
      );

      LocalDatabase.reset();

      await Durability.load();
      Durability.restore(true);

      assert.strictEqual(
        LocalDatabase.baseRow(COUNTED, "c1").n,
        9007199254740993n,
      );
    });

    it("brings a queued write's big integer back as a BigInt", async () => {
      await Durability.open();
      await Durability.load();

      const batch = unfiledBatch();

      batch.writes[0] = {
        ...batch.writes[0],
        deltas: {n: Model.unbox(Type.integer(9007199254740993n), "integer")},
      };

      await Durability.fileBatch(batch);

      const [record] = await Durability.batchesAbove(0);

      assert.strictEqual(record.writes[0].deltas.n, 9007199254740993n);
    });
  });

  describe("persistLanded()", () => {
    it("rewrites the record with the marks", async () => {
      await Durability.open();
      await Durability.load();

      const batch = sealedBatch(7);

      await writeBatches([batch.record()]);

      batch.land(new Set(["MyApp.Task t1"]));

      await Durability.persistLanded(batch);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.landed),
        [[0]],
      );
    });

    // A frame can land the writes of a batch that is not the newest one sealed - the counter
    // belongs to whatever was sealed last, and putting this batch's number down would walk it
    // backwards, onto a number a later batch has already spent.
    it("leaves the counter where it was", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(7);
      await storeBatch(8);

      await Durability.persistLanded(sealedBatch(7));

      assert.equal(await readMeta("seq"), 8);
    });

    // Another tab heard more frames and stored more marks: a mark lost is a move a later read of
    // the store promotes a second time.
    it("keeps the marks the record already holds", async () => {
      await Durability.open();
      await Durability.load();

      const batch = new Batch(null);

      batch.actorUserId = "u1";
      batch.append({id: "t1", op: "delete", type: "MyApp.Task"});
      batch.append({id: "t2", op: "delete", type: "MyApp.Task"});
      batch.seal(7);

      await writeBatches([{...batch.record(), landed: [1]}]);

      batch.land(new Set(["MyApp.Task t1"]));

      await Durability.persistLanded(batch);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.landed),
        [[0, 1]],
      );
    });

    // The record's shape is frozen: a record an older bundle wrote has no marks at all.
    it("takes a record with no marks as one with none landed", async () => {
      await Durability.open();
      await Durability.load();

      const batch = new Batch(null);

      batch.actorUserId = "u1";
      batch.append({id: "t1", op: "delete", type: "MyApp.Task"});
      batch.seal(7);

      const {landed: _landed, ...older} = batch.record();

      await writeBatches([older]);

      batch.land(new Set(["MyApp.Task t1"]));

      await Durability.persistLanded(batch);

      assert.equal(Durability.mode, "indexeddb");

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.landed),
        [[0]],
      );
    });

    // A later frame's mark has its own write coming, behind that frame's rows: written here, it
    // would go down ahead of them.
    it("writes the marks as they stood when asked, not when the record answers", async () => {
      await Durability.open();
      await Durability.load();

      const batch = new Batch(null);

      batch.actorUserId = "u1";
      batch.append({id: "t1", op: "delete", type: "MyApp.Task"});
      batch.append({id: "t2", op: "delete", type: "MyApp.Task"});
      batch.seal(7);

      await writeBatches([batch.record()]);

      batch.land(new Set(["MyApp.Task t1"]));

      const writing = Durability.persistLanded(batch);

      batch.land(new Set(["MyApp.Task t2"]));

      await writing;

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.landed),
        [[0]],
      );
    });

    // The tab that sent it was answered and let go of it: written back, the next page load would
    // send an answered batch again.
    it("writes nothing for a batch the queue no longer holds", async () => {
      await Durability.open();
      await Durability.load();
      await storeBatch(8);

      const batch = sealedBatch(7);

      batch.land(new Set(["MyApp.Task t1"]));

      await Durability.persistLanded(batch);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [8],
      );
    });
  });

  describe("persistReplica()", () => {
    it("leaves another user's pair", async () => {
      const pair = {id: "r-other", token: "statement-other"};

      await Durability.open();
      await Durability.load();
      await writeMeta({"replica:u9": pair});

      await Durability.persistReplica({id: "r1", token: "statement"});

      assert.deepStrictEqual(await readPair("u9"), pair);
    });

    // The actor moves at a page visit while the pair stays the document's.
    it("writes under the user the pair was taken up for", async () => {
      await seedPreviousLoad();
      await writeMeta({"replica:u2": {id: "r-u2", token: "statement-u2"}});
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      LocalDatabase.actorUserId = "u2";

      await Durability.persistReplica({id: "r-u1b", token: "statement-u1b"});

      assert.equal((await readPair("u1")).id, "r-u1b");
      assert.equal((await readPair("u2")).id, "r-u2");
    });

    it("keeps an id and the same id spelled as a string apart", async () => {
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "i1";
      await Durability.persistReplica({id: "r-number", token: "statement"});

      LocalDatabase.actorUserId = "s1";
      await Durability.persistReplica({id: "r-string", token: "statement"});

      assert.equal((await readPair("i1")).id, "r-number");
      assert.equal((await readPair("s1")).id, "r-string");
    });

    it("writes the pair", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.persistReplica({id: "r1", token: "statement"});

      assert.deepStrictEqual(await readPair(), {
        id: "r1",
        token: "statement",
      });
    });

    // Writes to the store commit in the order they were made, so the last one settled is all of
    // them settled.
    it("answers the write for replicaWritten() to wait on", async () => {
      await Durability.open();
      await Durability.load();

      Durability.persistReplica({id: "r1", token: "statement"});

      const writing = Durability.persistReplica({
        id: "r2",
        token: "statement-2",
      });

      assert.strictEqual(Durability.replicaWritten(), writing);
      assert.isFalse(await isSettled(Durability.replicaWritten()));

      await writing;

      assert.isTrue(await isSettled(Durability.replicaWritten()));
    });

    // A tab that follows another user before that user's stream handed it a pair holds none, and
    // a pair of nulls stored would be taken up as the pair a later page load presents.
    it("leaves a stored pair when the tab holds none", async () => {
      const pair = {id: "r1", token: "statement"};

      await Durability.open();
      await Durability.load();
      await writeMeta({"replica:anonymous": pair});

      await Durability.persistReplica({id: null, token: null});

      assert.deepStrictEqual(await readPair(), pair);
    });

    it("leaves nothing for replicaWritten() to wait on in memory mode", async () => {
      Durability.persistReplica({id: "r1", token: "statement"});

      assert.isTrue(await isSettled(Durability.replicaWritten()));
    });
  });

  describe("readBase()", () => {
    it("answers the stored place and every row, when the place differs", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      assert.deepStrictEqual(await Durability.readBase("place-0"), {
        cursor: "place-1",
        landed: [],
        owner: "u1",
        records: [taskRecord("t1", "Draft copy")],
      });
    });

    // The same place is the same rows: every write of a place writes its rows with it.
    it("answers the stored place and no rows, when the place is the one given", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      assert.deepStrictEqual(await Durability.readBase("place-1"), {
        cursor: "place-1",
        owner: "u1",
        records: null,
      });
    });

    it("answers the stored place and every row, when the tab holds no place", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      assert.deepStrictEqual(await Durability.readBase(null), {
        cursor: "place-1",
        landed: [],
        owner: "u1",
        records: [taskRecord("t1", "Draft copy")],
      });
    });

    // Rows with no place are a fill that never finished, which nothing takes up.
    it("answers no place and no rows, when the store holds no place", async () => {
      await seedPreviousLoad({cursor: undefined});
      await Durability.open();
      await Durability.load();

      assert.deepStrictEqual(await Durability.readBase("place-1"), {
        cursor: null,
        owner: "u1",
        records: null,
      });

      assert.deepStrictEqual(await Durability.readBase(null), {
        cursor: null,
        owner: "u1",
        records: null,
      });
    });

    // What the tab that led wrote since this tab loaded.
    it("reads the store as it is now, not as it was loaded", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();
      await Durability.persistFrame([taskRecord("t2", "Later")], "place-2");

      assert.deepStrictEqual(await Durability.readBase("place-1"), {
        cursor: "place-2",
        landed: [],
        owner: "u1",
        records: [taskRecord("t1", "Draft copy"), taskRecord("t2", "Later")],
      });
    });

    // A write made right after the read began lands after the whole read, not between the place
    // and its rows.
    it("reads the place and its rows as one", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const reading = Durability.readBase("place-0");

      const writing = Durability.persistFrame(
        [taskRecord("t2", "Later")],
        "place-2",
      );

      assert.equal(Durability.inFlight, 1);

      assert.deepStrictEqual(await reading, {
        cursor: "place-1",
        landed: [],
        owner: "u1",
        records: [taskRecord("t1", "Draft copy")],
      });

      await writing;
    });

    // One store serves every user of the browser, each in a group of their own.
    it("answers who the store belongs to", async () => {
      await seedPreviousLoad({actorUserId: "u2"});
      await Durability.open();
      await Durability.load();

      assert.equal((await Durability.readBase("place-1")).owner, "u2");
    });

    it("answers nobody as the owner of a store nobody signed in to", async () => {
      await seedPreviousLoad({actorUserId: undefined});
      await Durability.open();
      await Durability.load();

      assert.isNull((await Durability.readBase("place-1")).owner);
    });

    // A stored frame can have landed a batch a tab holds unlanded.
    it("answers what the queue records as landed, with the rows", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const batch = sealedBatch(7);

      batch.land(new Set(["MyApp.Task t1"]));

      await writeBatches([batch.record()]);

      assert.deepStrictEqual((await Durability.readBase("place-0")).landed, [
        {landed: [0], seq: 7},
      ]);
    });

    it("answers no marks for a stored batch that predates them", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const {landed: _landed, ...older} = sealedBatch(7).record();

      await writeBatches([older]);

      assert.deepStrictEqual((await Durability.readBase("place-0")).landed, [
        {landed: [], seq: 7},
      ]);
    });

    it("answers nothing in memory mode", async () => {
      assert.isNull(await Durability.readBase("place-1"));
      assert.equal(Durability.mode, "memory");
    });

    // Nothing has been lost, so it does not take the storage down the way a failed WRITE does.
    it("answers nothing when the store cannot be read, and goes on storing", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      sinon
        .stub(FDBDatabase.prototype, "transaction")
        .throws(new DOMException("The read was refused.", "UnknownError"));

      assert.isNull(await Durability.readBase("place-0"));
      assert.equal(Durability.mode, "indexeddb");
    });

    it("answers nothing when the rows cannot be read", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      sinon
        .stub(FDBObjectStore.prototype, "getAll")
        .throws(new DOMException("The read was refused.", "UnknownError"));

      assert.isNull(await Durability.readBase("place-0"));
      assert.equal(Durability.inFlight, 0);
    });
  });

  describe("repair()", () => {
    it("writes nothing when the store already holds the place", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const repairing = Durability.repair(
        [taskRecord("t2", "in memory")],
        "place-1",
      );

      assert.isFalse(await repairing);

      assert.equal(Durability.inFlight, 0);

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t1"],
      );
    });

    it("rewrites the rows and the place when the store names another", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Clock.observe(1_756_100_000_999_000);

      await Durability.repair(
        [taskRecord("t2", "second"), taskRecord("t3", "third")],
        "place-2",
      );

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2", "t3"],
      );

      assert.equal(await readMeta("cursor"), "place-2");
      assert.equal(await readMeta("clock"), 1_756_100_000_999_000);
    });

    // A store with no place may have been cleared by a start-over nobody heard of, and whatever
    // emptied it, the rows the tab holds are not what it vouches for - so the tab starts over.
    it("writes nothing and says so when the store holds no place", async () => {
      await seedPreviousLoad({cursor: undefined});
      await Durability.open();
      await Durability.load();

      assert.isTrue(
        await Durability.repair([taskRecord("t2", "second")], "place-2"),
      );

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t1"],
      );

      assert.isUndefined(await readMeta("cursor"));
    });

    it("says the store held a place when it rewrote it", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      assert.isFalse(
        await Durability.repair([taskRecord("t2", "second")], "place-2"),
      );
    });

    // A tab handed the lead while starting asks for the repair from its restore, and its page opens
    // the stream right after - so the stream's first frame can be stored while the repair is still
    // deciding, and has to land on top of it rather than under it.
    it("keeps a frame stored while it runs", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const repairing = Durability.repair(
        [taskRecord("t2", "in memory")],
        "place-2",
      );

      const persisting = Durability.persistFrame(
        [taskRecord("t3", "from the new stream")],
        "place-3",
      );

      await Promise.all([repairing, persisting]);

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2", "t3"],
      );

      assert.equal(await readMeta("cursor"), "place-3");
    });

    // Skipped, the repair would leave the store naming another place with nothing to say so.
    it("stops storing when the store cannot be read", async () => {
      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      sinon
        .stub(FDBDatabase.prototype, "transaction")
        .throws(new DOMException("The read was refused.", "UnknownError"));

      assert.isFalse(
        await Durability.repair([taskRecord("t2", "second")], "place-2"),
      );

      assert.equal(Durability.mode, "memory");
      sinon.assert.calledOnceWithExactly(posting, {kind: "storage_failed"});
    });

    it("does nothing in memory mode", async () => {
      assert.isFalse(
        await Durability.repair([taskRecord("t2", "second")], "place-2"),
      );

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
    });
  });

  describe("restore()", () => {
    it("fills the database with the stored rows and answers the place they are dated at", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.deepStrictEqual(LocalDatabase.baseRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });

      assert.equal(resumed.cursor, "place-1");
    });

    it("adopts the stored identity over the page's", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      assert.equal(Replica.id, "r-stored");
      assert.equal(Replica.token, "statement-stored");
    });

    // The stored clock has to be AHEAD of this machine's wall clock for the lifting to be
    // observable at all: a stamp is at least the wall clock, so a stored value in the past is
    // cleared without anything being resumed. Ahead is also the case that matters - a burst of
    // stamps inside one millisecond runs ahead of the wall clock, and a clock set back leaves
    // every earlier stamp above it.
    it("answers the stored counter and lifts the clock above it", async () => {
      const stored = Date.now() * 1024 + 10_000_000;

      await seedPreviousLoad({clock: stored});
      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.equal(resumed.seq, 41);
      assert.isAbove(Clock.stamp(), stored);
    });

    // Rows written by a fill that never finished. Nothing dates them, so the server cannot be
    // asked what changed since - and a row deleted while this browser was away would never be
    // taken off the screen.
    // Sent under the user of the session that sends them, so a page takes up only what its own
    // user made - and reads them back in the order they were made, which is the order they ship.
    it("answers the stored batches of the page's own user, oldest first", async () => {
      await seedPreviousLoad();
      await writeBatches([
        batchRecord(9),
        batchRecord(7),
        batchRecord(8, "u2"),
      ]);
      await Durability.open();
      await Durability.load();

      assert.deepStrictEqual(
        Durability.restore(true).batches.map((record) => record.seq),
        [7, 9],
      );
    });

    // Not dropped and not sent - somebody else's unfinished work, waiting for a page that mounts
    // under them. Nothing else can deliver it: the server knows nothing of a batch never sent.
    it("leaves another user's batches in the store", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad();
      await writeBatches([batchRecord(7), batchRecord(8, "u2")]);
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "u2";

      assert.deepStrictEqual(
        Durability.restore(true).batches.map((record) => record.seq),
        [8],
      );

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [7, 8],
      );
    });

    it("treats two anonymous loads as one owner's batches", async () => {
      await seedPreviousLoad({actorUserId: null});
      await writeBatches([batchRecord(7, null)]);
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = null;

      assert.deepStrictEqual(
        Durability.restore(true).batches.map((record) => record.seq),
        [7],
      );
    });

    // The rows going does not take the queue with it. A pending write over a base that has started
    // again is the resync case: a create folds as a new row, and an update waits for the fill to
    // bring the row its revisions are weighed against.
    it("answers the batches when the stored rows are refused", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad({cursor: null});
      await writeBatches([batchRecord(7)]);
      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.isNull(resumed.cursor);

      assert.deepStrictEqual(
        resumed.batches.map((record) => record.seq),
        [7],
      );
    });

    // A storage failure drops the counter and keeps the queue, so the two can disagree - and
    // counting from below a stored batch would hand its number to something else, overwriting its
    // record with a batch that is not it.
    it("counts on from above the stored batches when the counter was dropped", async () => {
      await createSchema();
      await writeBatches([batchRecord(4)]);

      LocalDatabase.actorUserId = "u1";

      await Durability.open();
      await Durability.load();

      assert.equal(Durability.restore(true).seq, 4);
    });

    // The other tabs hold the same rows out of the same store, and are told to let go the way a
    // server resync tells everyone - one judgement, made once, for the group.
    it("tells the group to start over when it refuses the stored rows", async () => {
      sinon.stub(Durability, "clear");

      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad({cursor: undefined});
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      sinon.assert.calledOnceWithExactly(posting, {
        event: "sync_resync",
        frame: {reason: "no place to resume from"},
        kind: "frame",
      });
    });

    // Every tab of the group was mounted for this tab's user, so what it holds is its own page's.
    // The word `identity` would drop those rows at once.
    it("tells the group to refill in place when the store was somebody else's", async () => {
      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "u2";

      Durability.restore(true);

      await Durability.replicaWritten();

      sinon.assert.calledOnceWithExactly(posting, {
        event: "sync_resync",
        frame: {reason: "somebody else is signed in"},
        kind: "frame",
      });
    });

    it("leaves a tab of the same user the row its page carried", async () => {
      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "u2";

      Durability.restore(true);

      await Durability.replicaWritten();

      const {event, frame} = posting.firstCall.args[0];

      // The other tab of the group, mounted for the same user.
      LocalDatabase.reset();
      LocalDatabase.putRow("MyApp.Task", {id: "t2", title: "Carried"});
      LocalDatabase.markCarried("MyApp.Task", "t2");

      SyncStream.receiveFrame(event, frame);

      assert.deepStrictEqual(LocalDatabase.baseRow("MyApp.Task", "t2"), {
        id: "t2",
        title: "Carried",
      });
    });

    it("makes somebody else's store this user's", async () => {
      sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "u2";

      Durability.restore(true);

      await Durability.replicaWritten();

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));
      assert.equal(await readMeta("actorUserId"), "u2");

      assert.deepStrictEqual(await readPair(), {
        id: "r-fresh",
        token: "statement-fresh",
      });
    });

    it("tells the group nothing when it takes the stored rows", async () => {
      const posting = sinon.stub(Tabs, "post");

      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      sinon.assert.notCalled(posting);
    });

    // A follower takes what the store holds and judges nothing: the leader judges once for the
    // group, and a follower that took stale rows is told to start over by it. What that buys is
    // the case where a follower's own judgement would be WRONG - rows with no place because the
    // leader is filling right now, half of a base the frames are about to complete.
    describe("for a follower", () => {
      it("takes the rows when there is no place to resume from", async () => {
        const clearing = sinon.stub(Durability, "clear");

        await seedPreviousLoad({cursor: undefined});
        await Durability.open();
        await Durability.load();

        const resumed = Durability.restore(false);

        assert.deepStrictEqual(LocalDatabase.baseRow("MyApp.Task", "t1"), {
          id: "t1",
          title: "Draft copy",
        });

        assert.isNull(resumed.cursor);
        assert.isFalse(clearing.called);
      });

      // Until the leader has judged the store, a query would answer from another person's rows.
      it("takes no rows and no place from somebody else's store, and clears nothing", async () => {
        await seedPreviousLoad();
        await Durability.open();
        await Durability.load();

        LocalDatabase.actorUserId = "u2";

        const resumed = Durability.restore(false);

        assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
        assert.isNull(resumed.cursor);
        assert.equal(Replica.id, "r-fresh");

        assert.equal((await readAll("entities")).length, 1);
        assert.equal(await readMeta("cursor"), "place-1");
        assert.equal(await readMeta("actorUserId"), "u1");
      });

      it("adopts a stored identity", async () => {
        await seedPreviousLoad();
        await Durability.open();
        await Durability.load();

        Durability.restore(false);

        assert.equal(Replica.id, "r-stored");
      });

      it("writes no identity when none is stored", async () => {
        await seedPreviousLoad({replica: undefined});
        await Durability.open();
        await Durability.load();

        Durability.restore(false);

        assert.equal(Replica.id, "r-fresh");
        assert.isUndefined(await readPair());
      });

      it("writes no owner", async () => {
        await seedPreviousLoad({actorUserId: "u2"});
        await Durability.open();
        await Durability.load();

        Durability.restore(false);

        assert.equal(await readMeta("actorUserId"), "u2");
      });

      it("tells the group nothing", async () => {
        const posting = sinon.stub(Tabs, "post");

        await seedPreviousLoad({cursor: undefined});
        await Durability.open();
        await Durability.load();

        Durability.restore(false);

        sinon.assert.notCalled(posting);
      });
    });

    it("drops the rows when no place was stored", async () => {
      const clearing = sinon.stub(Durability, "clear");

      await seedPreviousLoad({cursor: undefined});
      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.isNull(resumed.cursor);
      assert.isTrue(clearing.calledOnce);
    });

    // Not "drops the rows when the model changed" - there is nothing to drop. A bundle on another
    // model never sees the old model's database at all, and the old one is left exactly as it was
    // for the tabs still on it.
    it("finds nothing under another model, and leaves the old model's database alone", async () => {
      await seedPreviousLoad();

      globalThis.Hologram.sync = {modelHash: "model-b"};

      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.isNull(resumed.cursor);
      assert.equal(resumed.seq, 0);

      assert.equal((await readAll("entities", DATABASE_NAME)).length, 1);
    });

    // Their rows are what SOMEBODY ELSE was allowed to see, and a resuming stream is told what
    // moved rather than what this client should no longer be holding - so they would stay.
    it("drops the rows and the identity when somebody else is signed in", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad();

      LocalDatabase.actorUserId = "u2";

      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.equal(Replica.id, "r-fresh");
    });

    // Two visitors on one browser share a session-bound identity the server already treats as one,
    // so nobody has become anybody.
    it("treats two anonymous loads as one owner", async () => {
      await seedPreviousLoad({actorUserId: null});

      LocalDatabase.actorUserId = null;

      await Durability.open();
      await Durability.load();

      const resumed = Durability.restore(true);

      assert.equal(resumed.cursor, "place-1");
      assert.equal(Replica.id, "r-stored");
    });

    // Their queued batches were numbered under it, and sent under another pair a batch whose answer
    // was lost would be applied twice.
    it("takes up this user's own pair from a store somebody else holds", async () => {
      sinon.stub(Tabs, "post");

      await seedPreviousLoad({
        actorUserId: "u2",
        replica: {id: "r-u2", token: "statement-u2"},
      });

      await writeMeta({"replica:u1": {id: "r-u1", token: "statement-u1"}});

      LocalDatabase.actorUserId = "u1";

      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      await Durability.replicaWritten();

      assert.equal(Replica.id, "r-u1");

      assert.deepStrictEqual(await readPair("u1"), {
        id: "r-u1",
        token: "statement-u1",
      });

      assert.deepStrictEqual(await readPair("u2"), {
        id: "r-u2",
        token: "statement-u2",
      });
    });

    it("writes the page's pair when none was stored", async () => {
      await seedPreviousLoad({replica: undefined});
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      assert.equal(Replica.id, "r-fresh");

      // The first send waits for it.
      assert.isFalse(await isSettled(Durability.replicaWritten()));

      await Durability.replicaWritten();

      assert.deepStrictEqual(await readPair(), {
        id: "r-fresh",
        token: "statement-fresh",
      });
    });

    it("remembers who this page belongs to", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad({actorUserId: null});

      LocalDatabase.actorUserId = "u1";

      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      await storeBatch(41);

      assert.equal(await readMeta("actorUserId"), "u1");
    });

    it("answers nothing to resume from in memory mode", () => {
      assert.isNull(Durability.restore(true));
    });

    // Called once per page visit, and only the first visit has anything to take up. A later one
    // answering a place of null would take away the place the stream had been keeping.
    it("answers nothing the second time it is asked", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);

      assert.isNull(Durability.restore(true));
    });
  });

  describe("claim()", () => {
    const replica = {id: "r-claimed", token: "statement-claimed"};

    it("wipes another owner's rows and place, and writes the owner and the pair", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      await Durability.claim("u2", replica);

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));
      assert.equal(await readMeta("actorUserId"), "u2");
      assert.deepStrictEqual(await readPair("u2"), replica);
    });

    it("writes a new claim id when the owner changes", async () => {
      await seedPreviousLoad({claim: "claim-before"});
      await Durability.open();
      await Durability.load();

      await Durability.claim("u2", replica);

      const claim = await readMeta("claim");

      assert.isString(claim);
      assert.notEqual(claim, "claim-before");
    });

    it("keeps the claim id when the store is already this user's", async () => {
      await seedPreviousLoad({claim: "claim-before"});
      await Durability.open();
      await Durability.load();

      await Durability.claim("u1", replica);

      assert.equal(await readMeta("claim"), "claim-before");
    });

    it("writes a claim id when a visitor takes the store", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      await Durability.claim(null, replica);

      assert.isString(await readMeta("claim"));
    });

    // They come back to it, with batches numbered under it.
    it("leaves the previous owner's pair", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      await Durability.claim("u2", replica);

      assert.deepStrictEqual(await readPair("u1"), {
        id: "r-stored",
        token: "statement-stored",
      });
    });

    // A tab can have read the store before another tab of its group claimed it.
    it("keeps the rows and the place of a store already this user's", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      await Durability.claim("u1", replica);

      assert.equal((await readAll("entities")).length, 1);
      assert.equal(await readMeta("cursor"), "place-1");
      assert.equal(await readMeta("actorUserId"), "u1");
      assert.deepStrictEqual(await readPair(), replica);
    });

    it("takes a store for a visitor", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      await Durability.claim(null, replica);

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isNull(await readMeta("actorUserId"));
    });

    it("leaves the queue alone", async () => {
      await seedPreviousLoad();
      await writeBatches([batchRecord(7)]);
      await Durability.open();
      await Durability.load();

      await Durability.claim("u2", replica);

      assert.equal((await readAll("queue")).length, 1);
    });

    // Apart, a tab reading between the two would find an empty store under the previous owner.
    it("does it all in one transaction", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const transaction = sinon.spy(FDBDatabase.prototype, "transaction");

      await Durability.claim("u2", replica);

      sinon.assert.calledOnce(transaction);
    });

    it("is what a send waits for", async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      const claiming = Durability.claim("u2", replica);

      assert.strictEqual(Durability.replicaWritten(), claiming);

      await claiming;
    });
  });

  // One store serves every user of a browser, and the last page load to claim it owns it. A tab of
  // anyone else goes on from memory, and what it stores must not land among the owner's rows.
  describe("a store another user owns", () => {
    const replica = {id: "r-u2", token: "statement-u2"};

    const expectOwnerUntouched = async () => {
      assert.deepStrictEqual(await readAll("entities"), [
        taskRecord("t1", "Draft copy"),
      ]);

      assert.equal(await readMeta("cursor"), "place-1");
      assert.equal(await readMeta("actorUserId"), "u1");
    };

    beforeEach(async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      LocalDatabase.actorUserId = "u2";
    });

    it("takes no frame's rows or place", async () => {
      await Durability.persistFrame(
        [
          taskRecord("t2", "Not theirs"),
          {id: "t1", row: null, type: "MyApp.Task"},
        ],
        "place-2",
      );

      await expectOwnerUntouched();
    });

    it("still records where the clock stands", async () => {
      Clock.observe(1_756_100_000_999_000);

      await Durability.persistFrame([], "place-2");

      assert.equal(await readMeta("clock"), Clock.last());
    });

    it("is not cleared", async () => {
      await Durability.clear();

      await expectOwnerUntouched();
    });

    it("is not repaired, and does not read as placeless", async () => {
      assert.isFalse(
        await Durability.repair([taskRecord("t2", "Not theirs")], "place-2"),
      );

      await expectOwnerUntouched();
    });

    it("does not read as placeless with no place of its own", async () => {
      await writeMeta({actorUserId: "u1"});

      const {db} = await rawOpen();

      await new Promise((resolve) => {
        const transaction = db.transaction("meta", "readwrite");

        transaction.objectStore("meta").delete("cursor");
        transaction.oncomplete = resolve;
      });

      assert.isFalse(
        await Durability.repair([taskRecord("t2", "Not theirs")], "place-2"),
      );

      assert.isUndefined(await readMeta("cursor"));
    });

    it("keeps its rows through this tab's storage failure", async () => {
      await writeMeta({"replica:u2": replica});

      Replica.owner = "u2";

      // A pair the store cannot hold, so the write fails.
      Durability.persistReplica({id: () => {}, token: "statement"});

      await Durability.replicaWritten();

      assert.equal(Durability.mode, "memory");
      await expectOwnerUntouched();
      assert.isUndefined(await readPair("u2"));
      assert.equal((await readPair("u1")).id, "r-stored");
    });

    it("leaves this tab's queue and pair writable", async () => {
      Replica.owner = "u2";

      await Durability.persistFrame([], "place-2");
      await Durability.persistReplica(replica);

      const batch = unfiledBatch("u2");

      await Durability.fileBatch(batch);

      assert.deepStrictEqual(await readPair("u2"), replica);

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.actorUserId),
        ["u2"],
      );

      await expectOwnerUntouched();
    });

    // Back under this user through another tab, it holds rows this tab never saw, and a frame on
    // top would date them at a place they are not at.
    it("stays closed to a tab that lost it, when it comes back to that tab's user", async () => {
      await Durability.persistFrame([], "place-2");

      await writeMeta({
        actorUserId: "u2",
        claim: "claim-of-another-tab",
        cursor: "place-3",
      });

      await Durability.persistFrame(
        [taskRecord("t2", "Missed the frames before it")],
        "place-4",
      );

      assert.equal(await readMeta("cursor"), "place-3");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t1"],
      );
    });

    // The tab wrote nothing while the store was someone else's, so only the claim can tell it.
    it("stays closed to an idle tab when the store went away and came back", async () => {
      LocalDatabase.actorUserId = "u1";

      await writeMeta({
        actorUserId: "u1",
        claim: "claim-of-another-tab",
        cursor: "place-9",
      });

      await Durability.persistFrame(
        [taskRecord("t2", "One frame of many")],
        "place-10",
      );

      assert.equal(await readMeta("cursor"), "place-9");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t1"],
      );
    });

    // A follower can have read the store before its leader claimed it, and takes the lead later.
    it("takes up a newer claim of its own user through a repair", async () => {
      LocalDatabase.actorUserId = "u1";

      await writeMeta({claim: "claim-of-the-leader"});

      await Durability.repair([taskRecord("t2", "From memory")], "place-2");
      await Durability.persistFrame([taskRecord("t3", "Next")], "place-3");

      assert.equal(await readMeta("cursor"), "place-3");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2", "t3"],
      );
    });

    it("takes up a newer claim of its own user through a clear", async () => {
      LocalDatabase.actorUserId = "u1";

      await writeMeta({claim: "claim-of-the-leader"});

      await Durability.clear();
      await Durability.persistFrame([taskRecord("t2", "Refilled")], "place-2");

      assert.equal(await readMeta("cursor"), "place-2");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2"],
      );
    });

    it("takes up no claim through a clear it was refused", async () => {
      await writeMeta({claim: "claim-of-the-owner"});

      await Durability.clear();

      await writeMeta({actorUserId: "u2"});

      await Durability.persistFrame(
        [taskRecord("t2", "Not theirs")],
        "place-2",
      );

      assert.equal(await readMeta("cursor"), "place-1");
    });

    it("opens again once this tab claims it", async () => {
      await Durability.persistFrame([], "place-2");
      await Durability.claim("u2", replica);

      await Durability.persistFrame(
        [taskRecord("t2", "Theirs now")],
        "place-3",
      );

      assert.equal(await readMeta("cursor"), "place-3");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2"],
      );
    });

    // Transactions run in the order they were created, so the frame started before the claim is
    // refused and the one after it lands.
    it("takes a frame started right after this tab's claim", async () => {
      const refused = Durability.persistFrame(
        [taskRecord("t2", "Before the claim")],
        "place-2",
      );

      const claimed = Durability.claim("u2", replica);

      const taken = Durability.persistFrame(
        [taskRecord("t3", "After the claim")],
        "place-3",
      );

      await Promise.all([refused, claimed, taken]);

      assert.equal(await readMeta("cursor"), "place-3");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t3"],
      );
    });
  });

  // The frame refused while the actor was away is missing from the store, so a place stored after
  // it would claim rows that were never written.
  describe("a tab whose user changed and changed back", () => {
    beforeEach(async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);
      await Durability.replicaWritten();

      LocalDatabase.actorUserId = "u2";

      await Durability.persistFrame(
        [taskRecord("t2", "The frame refused")],
        "place-2",
      );

      LocalDatabase.actorUserId = "u1";
    });

    it("stores no frame past the one it was refused", async () => {
      await Durability.persistFrame(
        [taskRecord("t3", "The frame after it")],
        "place-3",
      );

      assert.equal(await readMeta("cursor"), "place-1");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t1"],
      );
    });

    it("stores frames again after a clear", async () => {
      await Durability.clear();

      await Durability.persistFrame(
        [taskRecord("t3", "The refill")],
        "place-3",
      );

      assert.equal(await readMeta("cursor"), "place-3");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t3"],
      );
    });

    it("stores frames again after a repair", async () => {
      await Durability.repair([taskRecord("t4", "From memory")], "place-4");

      await Durability.persistFrame(
        [taskRecord("t5", "The next frame")],
        "place-5",
      );

      assert.equal(await readMeta("cursor"), "place-5");

      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t4", "t5"],
      );
    });
  });

  // A navigation moves the actor while the tab still holds the previous user's rows and place.
  describe("a tab whose user changed at a navigation", () => {
    const expectNewUserUntouched = async () => {
      assert.deepStrictEqual(
        (await readAll("entities")).map((record) => record.id),
        ["t2"],
      );

      assert.equal(await readMeta("cursor"), "place-of-u2");
      assert.equal(await readMeta("actorUserId"), "u2");
    };

    beforeEach(async () => {
      await seedPreviousLoad();
      await Durability.open();
      await Durability.load();

      Durability.restore(true);
      await Durability.replicaWritten();

      // A page load of the new user takes the store and fills it.
      const {db} = await rawOpen();

      await new Promise((resolve) => {
        const transaction = db.transaction("entities", "readwrite");
        const entities = transaction.objectStore("entities");

        entities.clear();
        entities.put(taskRecord("t2", "The new user's"));
        transaction.oncomplete = resolve;
      });

      await writeMeta({
        actorUserId: "u2",
        claim: "claim-of-u2",
        cursor: "place-of-u2",
      });

      LocalDatabase.actorUserId = "u2";
    });

    it("does not repair the new user's store with the previous user's rows", async () => {
      assert.isFalse(
        await Durability.repair(
          [taskRecord("t1", "The old user's")],
          "place-1",
        ),
      );

      await expectNewUserUntouched();
    });

    it("does not clear the new user's store", async () => {
      await Durability.clear();

      await expectNewUserUntouched();
    });

    it("stores no frame in the new user's store", async () => {
      await Durability.persistFrame(
        [taskRecord("t3", "The old user's")],
        "place-2",
      );

      await expectNewUserUntouched();
    });

    it("does not wipe the new user's store on a storage failure", async () => {
      // A pair the store cannot hold, so the write fails.
      Durability.persistReplica({id: () => {}, token: "statement"});

      await Durability.replicaWritten();

      assert.equal(Durability.mode, "memory");
      await expectNewUserUntouched();
    });
  });

  describe("reset()", () => {
    it("deletes the database", async () => {
      await Durability.open();
      await Durability.load();
      await Durability.reset();

      const {db, upgraded} = await rawOpen();

      assert.isTrue(upgraded);
      assert.equal(Durability.mode, "memory");

      db.close();
    });
  });
});

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

import {
  assert,
  defineRuntimeGlobals,
  registerWebApis,
  sinon,
} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import Durability from "../../assets/js/durability.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Logger from "../../assets/js/logger.mjs";
import Replica from "../../assets/js/replica.mjs";

// registerWebApis puts sessionStorage on the global, which is where Logger writes - and every path
// through this module that gives up on storage says so through Logger.
defineRuntimeGlobals();
registerWebApis();

describe("Durability", () => {
  // Named for the store layout and the model the runtime globals below declare.
  const DATABASE_NAME = "hologram.1.model-a";

  // Installed for this suite and taken back down after it, never at module scope: mocha runs every
  // file in one process, and `open()` reads the absence of indexedDB as "this browser cannot
  // store" - so a factory left on the global would hand every later suite a working IndexedDB and
  // make its storage-mode answers depend on file order. Restored by deletion when it was absent,
  // so what comes after finds exactly what it would have found alone.
  let previousIndexedDB;

  before(() => {
    previousIndexedDB = globalThis.indexedDB;
    globalThis.indexedDB = fakeIndexedDB;
  });

  after(() => {
    if (previousIndexedDB === undefined) {
      delete globalThis.indexedDB;
    } else {
      globalThis.indexedDB = previousIndexedDB;
    }
  });

  // Every connection this suite opens for itself, closed centrally below.
  let raw = [];

  beforeEach(async () => {
    globalThis.Hologram.sync = {modelHash: "model-a"};

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

  const readMeta = async (key) => {
    const {db} = await rawOpen();

    return new Promise((resolve, reject) => {
      const request = db.transaction("meta").objectStore("meta").get(key);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);
    });
  };

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

    await writeMeta({
      actorUserId: "u1",
      clock: 1_756_100_000_123_004,
      cursor: "place-1",
      replica: {id: "r-stored", token: "statement-stored"},
      seq: 41,
      ...overrides,
    });

    LocalDatabase.actorUserId = "u1";
    Replica.offer({id: "r-fresh", token: "statement-fresh"});
  };

  describe("clear()", () => {
    it("drops the rows and the place, and keeps what this browser did", async () => {
      await Durability.open();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      await writeMeta({
        actorUserId: "u1",
        replica: {id: "r1", token: "statement"},
        seq: 41,
      });

      await Durability.clear();

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));

      assert.equal(await readMeta("actorUserId"), "u1");
      assert.equal(await readMeta("seq"), 41);

      assert.deepStrictEqual(await readMeta("replica"), {
        id: "r1",
        token: "statement",
      });
    });

    // A batch waiting to go out is this browser's own work rather than a copy of anything the
    // server holds, so the server replacing everything it says leaves it where it was.
    it("keeps the stored batches", async () => {
      await Durability.open();
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
    it("drops the identity and the counter, which have stopped being true", async () => {
      await Durability.open();
      await Durability.persistCounter(41);
      await Durability.persistReplica({id: "r1", token: "statement"});

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");
      assert.isUndefined(await readMeta("seq"));
      assert.isUndefined(await readMeta("replica"));
    });

    // It only ever moves forward, so it cannot go stale the way the counter does - and a clock
    // restarted low writes revisions the server reads as moved.
    it("keeps the clock", async () => {
      await Durability.open();
      await Durability.persistCounter(41);

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");
      assert.isNumber(await readMeta("clock"));
    });

    it("leaves nothing in flight", async () => {
      await Durability.open();
      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.inFlight, 0);
    });

    // Unlike the counter, a stored batch cannot go stale through this page carrying on: nothing
    // has answered it, and nothing will while there is nowhere to send it. It is the user's
    // unfinished work, and a later page load is the only thing that can still deliver it.
    it("keeps the stored batches", async () => {
      await Durability.open();
      await writeBatches([batchRecord(1)]);

      await Durability.persistFrame([unstorableRecord()], "place-1");

      assert.equal(Durability.mode, "memory");

      assert.deepStrictEqual(
        (await readAll("queue")).map((record) => record.seq),
        [1],
      );
    });
  });

  describe("forgetBatch()", () => {
    it("deletes the record of the given number and no other", async () => {
      await Durability.open();
      await Durability.persistBatch(sealedBatch(7));
      await Durability.persistBatch(sealedBatch(8));

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
    // A bundle carrying another store layout, or on another model, must open a database of its
    // own - which is what stops two tabs on different versions from ever sharing one.
    it("names the database for the layout of the store and the model it speaks", async () => {
      await Durability.open();

      const names = (await globalThis.indexedDB.databases()).map(
        (db) => db.name,
      );

      assert.include(names, "hologram.1.model-a");
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

    it("counts the stored batches when it opens", async () => {
      await createSchema();
      await writeBatches([batchRecord(1), batchRecord(2)]);

      assert.equal(Durability.storedBatches, 0);

      await Durability.open();

      assert.equal(Durability.storedBatches, 2);
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

    it("stays in memory mode when the build carries no data model", async () => {
      delete globalThis.Hologram.sync;

      await Durability.open();

      assert.equal(Durability.mode, "memory");
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
    it("lets the database go when another tab needs a new version", async () => {
      await Durability.open();
      await Durability.persistCounter(41);
      await Durability.persistReplica({id: "r1", token: "statement"});
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      const {db} = await rawOpen(2);

      assert.equal(Durability.mode, "memory");

      db.close();

      assert.equal(await readMeta("seq"), 41);
      assert.equal(await readMeta("cursor"), "place-1");
      assert.equal((await readAll("entities")).length, 1);

      assert.deepStrictEqual(await readMeta("replica"), {
        id: "r1",
        token: "statement",
      });
    });
  });

  describe("persistBatch()", () => {
    it("writes the batch, its number and the clock together", async () => {
      await Durability.open();

      Clock.observe(1_756_100_000_123_004);

      await Durability.persistBatch(sealedBatch(7));

      assert.deepStrictEqual(await readAll("queue"), [batchRecord(7)]);
      assert.equal(await readMeta("seq"), 7);
      assert.equal(await readMeta("clock"), 1_756_100_000_123_004);
    });

    // The sender waits on this one write before a batch goes out, so what it answers has to stay
    // pending until the batch is DOWN - not merely until it has been asked for. Nothing in flight
    // at the moment it settles is what says so, and one thing in flight before that is what says
    // the batch and its number went in a single transaction rather than two.
    it("answers a promise that settles once the batch is stored", async () => {
      await Durability.open();

      const writing = Durability.persistBatch(sealedBatch(7));

      assert.equal(Durability.inFlight, 1);

      await writing;

      assert.equal(Durability.inFlight, 0);
      assert.deepStrictEqual(await readAll("queue"), [batchRecord(7)]);
    });

    // A batch that has to be sent again is stored again - its marks may have moved since - and the
    // number it is keyed by is what makes the second write replace the first rather than pile up.
    it("replaces the record of the same number", async () => {
      await Durability.open();

      const batch = sealedBatch(7);

      await Durability.persistBatch(batch);

      batch.land(new Set(["MyApp.Task t1"]));

      await Durability.persistBatch(batch);

      assert.deepStrictEqual(await readAll("queue"), [batch.record()]);
    });

    // A browser with nowhere to store still has a sender waiting on this, so it answers something
    // already settled rather than nothing.
    it("answers an already-settled promise in memory mode", async () => {
      await Durability.persistBatch(sealedBatch(7));

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
      assert.notInclude(Logger.getLogs() ?? "", "durable storage stopped");
    });
  });

  describe("persistCounter()", () => {
    it("writes the number and the clock together", async () => {
      await Durability.open();

      Clock.observe(1_756_100_000_123_004);

      await Durability.persistCounter(41);

      assert.equal(await readMeta("seq"), 41);
      assert.equal(await readMeta("clock"), 1_756_100_000_123_004);
    });

    // The sender waits on this one write before a batch goes out, so what it answers has to stay
    // pending until the number is DOWN - not merely until it has been asked for. Nothing in flight
    // at the moment it settles is what says so: a promise that resolved early would settle with
    // the transaction still open, and the read below would pass anyway, having taken long enough
    // for the write to land on its own.
    it("answers a promise that settles once the number is stored", async () => {
      await Durability.open();

      const writing = Durability.persistCounter(41);

      assert.equal(Durability.inFlight, 1);

      await writing;

      assert.equal(Durability.inFlight, 0);
      assert.equal(await readMeta("seq"), 41);
    });

    // A browser with nowhere to store still has a sender waiting on this, so it answers something
    // already settled rather than nothing.
    it("answers an already-settled promise in memory mode", async () => {
      await Durability.persistCounter(41);

      assert.equal(Durability.mode, "memory");
      assert.equal(Durability.inFlight, 0);
      assert.notInclude(Logger.getLogs() ?? "", "durable storage stopped");
    });
  });

  describe("persistFrame()", () => {
    it("puts a held row's record and deletes a gone row's", async () => {
      await Durability.open();
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
      await Durability.persistFrame([], "place-1");
      await Durability.persistFrame([], null);

      assert.equal(await readMeta("cursor"), "place-1");
    });

    it("writes where the clock stands", async () => {
      await Durability.open();

      Clock.observe(1_756_100_000_123_004);

      await Durability.persistFrame([], "place-1");

      assert.equal(await readMeta("clock"), 1_756_100_000_123_004);
    });

    it("counts a transaction in flight until it completes", async () => {
      await Durability.open();

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

  describe("persistLanded()", () => {
    it("rewrites the record with the marks", async () => {
      await Durability.open();

      const batch = sealedBatch(7);

      await Durability.persistBatch(batch);

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
      await Durability.persistBatch(sealedBatch(7));
      await Durability.persistBatch(sealedBatch(8));

      await Durability.persistLanded(sealedBatch(7));

      assert.equal(await readMeta("seq"), 8);
    });
  });

  describe("persistReplica()", () => {
    it("writes the pair", async () => {
      await Durability.open();
      await Durability.persistReplica({id: "r1", token: "statement"});

      assert.deepStrictEqual(await readMeta("replica"), {
        id: "r1",
        token: "statement",
      });
    });
  });

  describe("restore()", () => {
    it("fills the database with the stored rows and answers the place they are dated at", async () => {
      await seedPreviousLoad();
      await Durability.open();

      const resumed = Durability.restore();

      assert.deepStrictEqual(LocalDatabase.baseRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });

      assert.equal(resumed.cursor, "place-1");
    });

    it("adopts the stored identity over the page's", async () => {
      await seedPreviousLoad();
      await Durability.open();

      Durability.restore();

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

      const resumed = Durability.restore();

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

      assert.deepStrictEqual(
        Durability.restore().batches.map((record) => record.seq),
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

      LocalDatabase.actorUserId = "u2";

      assert.deepStrictEqual(
        Durability.restore().batches.map((record) => record.seq),
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

      LocalDatabase.actorUserId = null;

      assert.deepStrictEqual(
        Durability.restore().batches.map((record) => record.seq),
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

      const resumed = Durability.restore();

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

      assert.equal(Durability.restore().seq, 4);
    });

    it("drops the rows when no place was stored", async () => {
      const clearing = sinon.stub(Durability, "clear");

      await seedPreviousLoad({cursor: undefined});
      await Durability.open();

      const resumed = Durability.restore();

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

      const resumed = Durability.restore();

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.isNull(resumed.cursor);
      assert.equal(resumed.seq, 0);

      assert.equal((await readAll("entities", "hologram.1.model-a")).length, 1);
    });

    // Their rows are what SOMEBODY ELSE was allowed to see, and a resuming stream is told what
    // moved rather than what this client should no longer be holding - so they would stay.
    it("drops the rows and the identity when somebody else is signed in", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad();

      LocalDatabase.actorUserId = "u2";

      await Durability.open();

      Durability.restore();

      assert.isNull(LocalDatabase.baseRow("MyApp.Task", "t1"));
      assert.equal(Replica.id, "r-fresh");
    });

    // Two visitors on one browser share a session-bound identity the server already treats as one,
    // so nobody has become anybody.
    it("treats two anonymous loads as one owner", async () => {
      await seedPreviousLoad({actorUserId: null});

      LocalDatabase.actorUserId = null;

      await Durability.open();

      const resumed = Durability.restore();

      assert.equal(resumed.cursor, "place-1");
      assert.equal(Replica.id, "r-stored");
    });

    it("writes the page's pair when none was stored", async () => {
      await seedPreviousLoad({replica: undefined});
      await Durability.open();

      Durability.restore();

      assert.equal(Replica.id, "r-fresh");

      await Durability.persistReplica(Replica.current());

      assert.deepStrictEqual(await readMeta("replica"), {
        id: "r-fresh",
        token: "statement-fresh",
      });
    });

    it("remembers who this page belongs to", async () => {
      sinon.stub(Durability, "clear");

      await seedPreviousLoad({actorUserId: null});

      LocalDatabase.actorUserId = "u1";

      await Durability.open();

      Durability.restore();

      await Durability.persistCounter(41);

      assert.equal(await readMeta("actorUserId"), "u1");
    });

    it("answers nothing to resume from in memory mode", () => {
      assert.isNull(Durability.restore());
    });

    // Called once per page visit, and only the first visit has anything to take up. A later one
    // answering a place of null would take away the place the stream had been keeping.
    it("answers nothing the second time it is asked", async () => {
      await seedPreviousLoad();
      await Durability.open();

      Durability.restore();

      assert.isNull(Durability.restore());
    });
  });

  describe("reset()", () => {
    it("deletes the database", async () => {
      await Durability.open();
      await Durability.reset();

      const {db, upgraded} = await rawOpen();

      assert.isTrue(upgraded);
      assert.equal(Durability.mode, "memory");

      db.close();
    });
  });
});

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
} from "./support/helpers.mjs";

import Clock from "../../assets/js/clock.mjs";
import Durability from "../../assets/js/durability.mjs";
import Logger from "../../assets/js/logger.mjs";

globalThis.indexedDB = fakeIndexedDB;

// registerWebApis puts sessionStorage on the global, which is where Logger writes - and every path
// through this module that gives up on storage says so through Logger.
defineRuntimeGlobals();
registerWebApis();

describe("Durability", () => {
  const DATABASE_NAME = "hologram";

  // Every connection this suite opens for itself, closed centrally below.
  let raw = [];

  beforeEach(async () => {
    globalThis.Hologram.sync = {modelHash: "model-a"};

    Clock.reset();
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

    Clock.reset();

    delete globalThis.Hologram.sync;
  });

  // Read back through a database of the test's own, never through the module under test - a module
  // trusted to read its own writes can agree with itself about a mistake in both directions.
  const rawOpen = (version = 1) =>
    new Promise((resolve, reject) => {
      const request = globalThis.indexedDB.open(DATABASE_NAME, version);
      let upgraded = false;

      request.onupgradeneeded = () => (upgraded = true);
      request.onerror = () => reject(request.error);

      request.onsuccess = () => {
        raw.push(request.result);
        resolve({db: request.result, upgraded});
      };
    });

  const readAll = async (storeName) => {
    const {db} = await rawOpen();

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

  describe("clear()", () => {
    it("drops the rows and the place, and keeps what this browser did", async () => {
      await Durability.open();
      await Durability.persistFrame(
        [taskRecord("t1", "Draft copy")],
        "place-1",
      );

      await writeMeta({
        actorUserId: "u1",
        modelHash: "model-a",
        replica: {id: "r1", token: "statement"},
        seq: 41,
      });

      await Durability.clear();

      assert.deepStrictEqual(await readAll("entities"), []);
      assert.isUndefined(await readMeta("cursor"));

      assert.equal(await readMeta("actorUserId"), "u1");
      assert.equal(await readMeta("modelHash"), "model-a");
      assert.equal(await readMeta("seq"), 41);

      assert.deepStrictEqual(await readMeta("replica"), {
        id: "r1",
        token: "statement",
      });
    });
  });

  describe("open()", () => {
    it("opens in indexeddb mode and creates the two object stores", async () => {
      await Durability.open();

      assert.equal(Durability.mode, "indexeddb");

      const {db} = await rawOpen();

      assert.deepStrictEqual(Array.from(db.objectStoreNames), [
        "entities",
        "meta",
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

    // Holding it open would block that tab for as long as this page lives, and the durability this
    // page gives up is one page's worth.
    it("lets the database go when another tab needs a new version", async () => {
      await Durability.open();

      const {db} = await rawOpen(2);

      assert.equal(Durability.mode, "memory");

      db.close();
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

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

import Durability from "../../assets/js/durability.mjs";

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

    await Durability.reset();
  });

  // The handles are closed HERE rather than at the end of each test, because a test that fails
  // never reaches its own close - and an open connection blocks deleteDatabase, so the next red
  // test would hang instead of failing. A hang says nothing about what broke.
  afterEach(async () => {
    raw.forEach((db) => db.close());
    raw = [];

    await Durability.reset();

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

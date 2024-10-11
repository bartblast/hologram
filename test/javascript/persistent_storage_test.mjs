"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import PersistentStorage from "../../assets/js/persistent_storage.mjs";

import FDBDatabase from "../../assets/node_modules/fake-indexeddb/build/esm/FDBDatabase.js";
import FDBFactory from "../../assets/node_modules/fake-indexeddb/build/esm/FDBFactory.js";

defineGlobalErlangAndElixirModules();

async function getAllObjects() {
  const db = await PersistentStorage.database();

  return new Promise((resolve) => {
    db
      .transaction(PersistentStorage.PAGE_SNAPSHOTS_OBJ_STORE_NAME, "readonly")
      .objectStore(PersistentStorage.PAGE_SNAPSHOTS_OBJ_STORE_NAME)
      .getAll().onsuccess = (event) => {
      resolve(event.target.result);
    };
  });
}

describe("PersistentStorage", () => {
  beforeEach(async () => {
    globalThis.indexedDB = new FDBFactory();
    PersistentStorage.env = "dev";
  });

  it("database()", async () => {
    const result = await PersistentStorage.database();

    assert.instanceOf(result, FDBDatabase);
    assert.equal(result.name, "hologram_dev");
    assert.equal(result.version, 1);

    assert.deepStrictEqual(result.objectStoreNames, ["pageSnapshots"]);

    const objectStore = result
      .transaction("pageSnapshots", "readonly")
      .objectStore("pageSnapshots");

    assert.equal(objectStore.keyPath, "id");
    assert.isFalse(objectStore.autoIncrement);
    assert.deepStrictEqual(objectStore.indexNames, ["createdAt"]);

    const index = objectStore.index("createdAt");
    assert.equal(index.keyPath, "createdAt");
    assert.isFalse(index.multiEntry);
    assert.isFalse(index.unique);
  });

  it("getPageSnapshot()", async () => {
    const id = crypto.randomUUID();
    const data = {a: 1, b: 2};

    // putPageSnapshot() can be used in this test,
    // because it was tested with low-level indexedDB functions only
    // (not using PersistentStorage class functions).
    await PersistentStorage.putPageSnapshot(id, data);

    const objects = await getAllObjects();

    const result = await PersistentStorage.getPageSnapshot(id);
    assert.deepStrictEqual(result, objects[0]);
  });

  it("init()", async () => {
    PersistentStorage.env = null;

    const result = await PersistentStorage.init("my_env");
    assert.instanceOf(result, FDBDatabase);

    assert.equal(PersistentStorage.env, "my_env");
  });

  it("putPageSnapshot()", async () => {
    const id = crypto.randomUUID();
    const data = {a: 1, b: 2};

    const result = await PersistentStorage.putPageSnapshot(id, data);
    assert.equal(result, id);

    const objects = await getAllObjects();

    const createdAt = objects[0].createdAt;
    assert.instanceOf(createdAt, Date);
    assert.deepStrictEqual(objects, [{id, data, createdAt}]);

    const nowMs = Date.now();
    const createdAtMs = createdAt.getTime();
    assert.isAtLeast(nowMs, createdAtMs);
    assert.isAtMost(Math.abs(nowMs - createdAtMs), 3000);
  });
});

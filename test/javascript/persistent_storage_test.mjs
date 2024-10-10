"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import PersistentStorage from "../../assets/js/persistent_storage.mjs";

import FDBDatabase from "../../assets/node_modules/fake-indexeddb/build/esm/FDBDatabase.js";

defineGlobalErlangAndElixirModules();

describe("PersistentStorage", () => {
  it("init()", async () => {
    const result = await PersistentStorage.init("dev");

    assert.instanceOf(result, FDBDatabase);
    assert.equal(PersistentStorage.db, result);
    assert.equal(result.name, "hologram_dev");
    assert.equal(result.version, 1);

    assert.deepStrictEqual(PersistentStorage.db.objectStoreNames, [
      "pageSnapshots",
    ]);

    const objectStore = PersistentStorage.db
      .transaction("pageSnapshots", "readonly")
      .objectStore("pageSnapshots");

    assert.isNull(objectStore.keyPath);
    assert.isTrue(objectStore.autoIncrement);
    assert.deepStrictEqual(objectStore.indexNames, ["createdAt"]);

    const index = objectStore.index("createdAt");
    assert.equal(index.keyPath, "createdAt");
    assert.isFalse(index.multiEntry);
    assert.isFalse(index.unique);
  });
});

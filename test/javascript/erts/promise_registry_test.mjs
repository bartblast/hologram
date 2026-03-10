"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ERTS from "../../../assets/js/erts.mjs";
import PromiseRegistry from "../../../assets/js/erts/promise_registry.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const ref1 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [3, 2, 1]);
const ref2 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [4, 3, 2]);

describe("PromiseRegistry", () => {
  beforeEach(() => {
    PromiseRegistry.clear();
  });

  it("clear()", () => {
    PromiseRegistry.put(ref1, Promise.resolve(1));
    PromiseRegistry.put(ref2, Promise.resolve(2));

    assert.equal(PromiseRegistry.promises.size, 2);

    PromiseRegistry.clear();

    assert.equal(PromiseRegistry.promises.size, 0);
  });

  describe("delete()", () => {
    it("removes the promise for the given reference", () => {
      PromiseRegistry.put(ref1, Promise.resolve(1));
      PromiseRegistry.put(ref2, Promise.resolve(2));

      PromiseRegistry.delete(ref1);

      assert.equal(PromiseRegistry.promises.size, 1);
      assert.isNull(PromiseRegistry.get(ref1));
      assert.isNotNull(PromiseRegistry.get(ref2));
    });

    it("does nothing when reference doesn't exist", () => {
      PromiseRegistry.put(ref1, Promise.resolve(1));

      PromiseRegistry.delete(ref2);

      assert.equal(PromiseRegistry.promises.size, 1);
    });
  });

  describe("get()", () => {
    it("returns promise when it exists", () => {
      const promise = Promise.resolve(42);
      PromiseRegistry.put(ref1, promise);

      const result = PromiseRegistry.get(ref1);

      assert.strictEqual(result, promise);
    });

    it("returns null when promise doesn't exist", () => {
      const result = PromiseRegistry.get(ref1);

      assert.isNull(result);
    });
  });

  describe("put()", () => {
    it("stores multiple promises with different references", () => {
      const promise1 = Promise.resolve(1);
      PromiseRegistry.put(ref1, promise1);

      const promise2 = Promise.resolve(2);
      PromiseRegistry.put(ref2, promise2);

      assert.equal(PromiseRegistry.promises.size, 2);

      assert.strictEqual(PromiseRegistry.get(ref1), promise1);
      assert.strictEqual(PromiseRegistry.get(ref2), promise2);
    });

    it("overwrites existing promise for the same reference", () => {
      const promise1 = Promise.resolve(1);
      const promise2 = Promise.resolve(2);

      PromiseRegistry.put(ref1, promise1);
      PromiseRegistry.put(ref1, promise2);

      assert.equal(PromiseRegistry.promises.size, 1);

      assert.strictEqual(PromiseRegistry.get(ref1), promise2);
    });
  });
});

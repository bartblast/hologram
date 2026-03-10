"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ERTS from "../../../assets/js/erts.mjs";
import NativeObjectRegistry from "../../../assets/js/erts/native_object_registry.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const ref1 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [3, 2, 1]);
const ref2 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [4, 3, 2]);

describe("NativeObjectRegistry", () => {
  beforeEach(() => {
    NativeObjectRegistry.clear();
  });

  it("clear()", () => {
    NativeObjectRegistry.put(ref1, {a: 1});
    NativeObjectRegistry.put(ref2, {b: 2});

    assert.equal(NativeObjectRegistry.objects.size, 2);

    NativeObjectRegistry.clear();

    assert.equal(NativeObjectRegistry.objects.size, 0);
  });

  describe("get()", () => {
    it("returns object when it exists", () => {
      const obj = {a: 1};
      NativeObjectRegistry.put(ref1, obj);

      const result = NativeObjectRegistry.get(ref1);

      assert.strictEqual(result, obj);
    });

    it("returns null when object doesn't exist", () => {
      const result = NativeObjectRegistry.get(ref1);

      assert.isNull(result);
    });
  });

  describe("put()", () => {
    it("stores multiple objects with different references", () => {
      const obj1 = {a: 1};
      NativeObjectRegistry.put(ref1, obj1);

      const obj2 = {b: 2};
      NativeObjectRegistry.put(ref2, obj2);

      assert.equal(NativeObjectRegistry.objects.size, 2);

      assert.strictEqual(NativeObjectRegistry.get(ref1), obj1);
      assert.strictEqual(NativeObjectRegistry.get(ref2), obj2);
    });

    it("overwrites existing object for the same reference", () => {
      const obj1 = {a: 1};
      const obj2 = {b: 2};

      NativeObjectRegistry.put(ref1, obj1);
      NativeObjectRegistry.put(ref1, obj2);

      assert.equal(NativeObjectRegistry.objects.size, 1);

      assert.strictEqual(NativeObjectRegistry.get(ref1), obj2);
    });
  });
});

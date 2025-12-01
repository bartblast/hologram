"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";
import Erlang_Sets from "../../../assets/js/erlang/sets.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Sets", () => {
  describe("subtract/2", () => {
    const subtract = Erlang_Sets["subtract/2"];

    it("removes elements in the second set from the first set", () => {
      const set1 = Type.map([
        [Type.integer(1), Type.atom("true")],
        [Type.integer(2), Type.atom("true")],
        [Type.integer(3), Type.atom("true")],
      ]);
      const set2 = Type.map([[Type.integer(2), Type.atom("true")]]);

      const result = subtract(set1, set2);
      const data = result.data;

      assert.isTrue(Type.isMap(result));
      assert.isDefined(data[Type.encodeMapKey(Type.integer(1))]);
      assert.isUndefined(data[Type.encodeMapKey(Type.integer(2))]);
      assert.isDefined(data[Type.encodeMapKey(Type.integer(3))]);
      assert.strictEqual(Object.keys(data).length, 2);
    });

    it("returns a new set without modifying the original sets", () => {
      const set1 = Type.map([
        [Type.integer(1), Type.atom("true")],
        [Type.integer(2), Type.atom("true")],
      ]);
      const set2 = Type.map([[Type.integer(2), Type.atom("true")]]);

      const result = subtract(set1, set2);

      // Original sets should remain unchanged
      assert.strictEqual(Object.keys(set1.data).length, 2);
      assert.isDefined(set1.data[Type.encodeMapKey(Type.integer(2))]);

      assert.strictEqual(Object.keys(set2.data).length, 1);
      assert.isDefined(set2.data[Type.encodeMapKey(Type.integer(2))]);

      // Result should have element removed
      assert.strictEqual(Object.keys(result.data).length, 1);
      assert.isDefined(result.data[Type.encodeMapKey(Type.integer(1))]);
    });

    it("returns the first set when the second set is empty", () => {
      const set1 = Type.map([
        [Type.integer(1), Type.atom("true")],
        [Type.integer(2), Type.atom("true")],
      ]);
      const set2 = Type.map();

      const result = subtract(set1, set2);

      assert.strictEqual(Object.keys(result.data).length, 2);
    });

    it("returns empty set when the first set is empty", () => {
      const set1 = Type.map();
      const set2 = Type.map([[Type.integer(1), Type.atom("true")]]);

      const result = subtract(set1, set2);

      assert.strictEqual(Object.keys(result.data).length, 0);
    });

    it("returns empty set when both sets are the same", () => {
      const set1 = Type.map([[Type.integer(1), Type.atom("true")]]);
      const set2 = Type.map([[Type.integer(1), Type.atom("true")]]);

      const result = subtract(set1, set2);

      assert.strictEqual(Object.keys(result.data).length, 0);
    });
  });
});

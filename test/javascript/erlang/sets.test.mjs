"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";
import Erlang_Sets from "../../../assets/js/erlang/sets.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test.
// Always update both together.

describe("Erlang_Sets", () => {
  describe("subtract/2", () => {
    const subtract = Erlang_Sets["subtract/2"];

    it("removes elements in the second set from the first set", () => {
      const set1 = new Map([
        [1, true],
        [2, true],
        [3, true],
      ]);
      const set2 = new Map([[2, true]]);

      const result = subtract(set1, set2);

      assert.strictEqual(result.has(1), true);
      assert.strictEqual(result.has(2), false);
      assert.strictEqual(result.has(3), true);
    });

    it("returns a new set without modifying the original sets", () => {
      const set1 = new Map([
        [1, true],
        [2, true],
      ]);
      const set2 = new Map([[2, true]]);

      const result = subtract(set1, set2);

      // Original sets should remain unchanged
      assert.strictEqual(set1.has(1), true);
      assert.strictEqual(set1.has(2), true);
      assert.strictEqual(set2.has(2), true);

      // Result should be different
      assert.strictEqual(result.has(1), true);
      assert.strictEqual(result.has(2), false);
    });

    it("returns empty set when both sets are the same", () => {
      const set1 = new Map([
        [1, true],
        [2, true],
      ]);
      const set2 = new Map([
        [1, true],
        [2, true],
      ]);

      const result = subtract(set1, set2);

      assert.strictEqual(result.size, 0);
    });

    it("returns the first set when the second set is empty", () => {
      const set1 = new Map([
        [1, true],
        [2, true],
      ]);
      const set2 = new Map();

      const result = subtract(set1, set2);

      assert.strictEqual(result.has(1), true);
      assert.strictEqual(result.has(2), true);
      assert.strictEqual(result.size, 2);
    });

    it("returns empty set when the first set is empty", () => {
      const set1 = new Map();
      const set2 = new Map([[1, true]]);

      const result = subtract(set1, set2);

      assert.strictEqual(result.size, 0);
    });
  });
});

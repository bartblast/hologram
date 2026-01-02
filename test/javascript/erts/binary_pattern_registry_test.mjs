"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import BinaryPatternRegistry from "../../../assets/js/erts/binary_pattern_registry.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const ref1 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [3, 2, 1]);
const ref2 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [4, 3, 2]);

describe("BinaryPatternRegistry", () => {
  beforeEach(() => {
    BinaryPatternRegistry.clear();
    ERTS.nodeTable.reset();
  });

  it("clear()", () => {
    BinaryPatternRegistry.put(ref1, "pattern_dummy_1");
    BinaryPatternRegistry.put(ref2, "pattern_dummy_2");

    assert.equal(BinaryPatternRegistry.patterns.size, 2);

    BinaryPatternRegistry.clear();

    assert.equal(BinaryPatternRegistry.patterns.size, 0);
  });

  describe("get()", () => {
    it("returns pattern when it exists", () => {
      BinaryPatternRegistry.put(ref1, "pattern_dummy");
      const result = BinaryPatternRegistry.get(ref1);

      assert.equal(result, "pattern_dummy");
    });

    it("returns null when pattern doesn't exist", () => {
      const result = BinaryPatternRegistry.get(ref1);

      assert.isNull(result);
    });
  });

  describe("put()", () => {
    it("stores multiple patterns with different references", () => {
      BinaryPatternRegistry.put(ref1, "pattern_dummy_1");
      BinaryPatternRegistry.put(ref2, "pattern_dummy_2");

      assert.equal(BinaryPatternRegistry.patterns.size, 2);

      assert.equal(BinaryPatternRegistry.get(ref1), "pattern_dummy_1");
      assert.equal(BinaryPatternRegistry.get(ref2), "pattern_dummy_2");
    });

    it("overwrites existing pattern for the same reference", () => {
      BinaryPatternRegistry.put(ref1, "pattern_dummy_1");
      BinaryPatternRegistry.put(ref1, "pattern_dummy_2");

      assert.equal(BinaryPatternRegistry.patterns.size, 1);

      assert.equal(BinaryPatternRegistry.get(ref1), "pattern_dummy_2");
    });
  });
});

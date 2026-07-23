"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ERTS from "../../../assets/js/erts.mjs";
import RegexPatternRegistry from "../../../assets/js/erts/regex_pattern_registry.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const ref1 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [3, 2, 1]);
const ref2 = Type.reference(ERTS.nodeTable.CLIENT_NODE, 0, [4, 3, 2]);

describe("RegexPatternRegistry", () => {
  beforeEach(() => {
    RegexPatternRegistry.clear();
    ERTS.nodeTable.reset();
  });

  it("clear()", () => {
    RegexPatternRegistry.put(ref1, "pattern_dummy_1");
    RegexPatternRegistry.put(ref2, "pattern_dummy_2");

    assert.equal(RegexPatternRegistry.patterns.size, 2);

    RegexPatternRegistry.clear();

    assert.equal(RegexPatternRegistry.patterns.size, 0);
  });

  describe("get()", () => {
    it("returns pattern when it exists", () => {
      RegexPatternRegistry.put(ref1, "pattern_dummy");
      const result = RegexPatternRegistry.get(ref1);

      assert.equal(result, "pattern_dummy");
    });

    it("returns null when pattern doesn't exist", () => {
      const result = RegexPatternRegistry.get(ref1);

      assert.isNull(result);
    });
  });

  describe("put()", () => {
    it("stores multiple patterns with different references", () => {
      RegexPatternRegistry.put(ref1, "pattern_dummy_1");
      RegexPatternRegistry.put(ref2, "pattern_dummy_2");

      assert.equal(RegexPatternRegistry.patterns.size, 2);

      assert.equal(RegexPatternRegistry.get(ref1), "pattern_dummy_1");
      assert.equal(RegexPatternRegistry.get(ref2), "pattern_dummy_2");
    });

    it("overwrites existing pattern for the same reference", () => {
      RegexPatternRegistry.put(ref1, "pattern_dummy_1");
      RegexPatternRegistry.put(ref1, "pattern_dummy_2");

      assert.equal(RegexPatternRegistry.patterns.size, 1);

      assert.equal(RegexPatternRegistry.get(ref1), "pattern_dummy_2");
    });
  });
});

"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import ERTS from "../../../assets/js/erts.mjs";
import RegexPatternRegistry from "../../../assets/js/erts/regex_pattern_registry.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

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
    RegexPatternRegistry.putImport("key_dummy", "imported_dummy");

    assert.equal(RegexPatternRegistry.patterns.size, 2);
    assert.equal(RegexPatternRegistry.imports.size, 1);

    RegexPatternRegistry.clear();

    assert.equal(RegexPatternRegistry.patterns.size, 0);
    assert.equal(RegexPatternRegistry.imports.size, 0);
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

  describe("getImport()", () => {
    it("returns what was stored under the key", () => {
      RegexPatternRegistry.putImport("key_dummy", "imported_dummy");
      const result = RegexPatternRegistry.getImport("key_dummy");

      assert.equal(result, "imported_dummy");
    });

    it("returns null when nothing was stored under the key", () => {
      const result = RegexPatternRegistry.getImport("key_dummy");

      assert.isNull(result);
    });
  });

  describe("importKey()", () => {
    const source = Type.bitstring("ab");

    it("is the same for equal sources and options", () => {
      const key1 = RegexPatternRegistry.importKey(
        Type.bitstring("ab"),
        Type.list([Type.atom("caseless")]),
      );

      const key2 = RegexPatternRegistry.importKey(
        Type.bitstring("ab"),
        Type.list([Type.atom("caseless")]),
      );

      assert.equal(key1, key2);
    });

    it("differs for different sources", () => {
      const key1 = RegexPatternRegistry.importKey(source, Type.list());

      const key2 = RegexPatternRegistry.importKey(
        Type.bitstring("ac"),
        Type.list(),
      );

      assert.notEqual(key1, key2);
    });

    it("differs for different options", () => {
      const key1 = RegexPatternRegistry.importKey(source, Type.list());

      const key2 = RegexPatternRegistry.importKey(
        source,
        Type.list([Type.atom("caseless")]),
      );

      assert.notEqual(key1, key2);
    });
  });

  describe("lookupByTerm()", () => {
    const rePatternTuple = (ref) =>
      Type.tuple([
        Type.atom("re_pattern"),
        Type.integer(0),
        Type.integer(0),
        Type.integer(0),
        ref,
      ]);

    it("returns the entry of a registered compiled pattern tuple", () => {
      RegexPatternRegistry.put(ref1, "pattern_dummy");

      assert.equal(
        RegexPatternRegistry.lookupByTerm(rePatternTuple(ref1)),
        "pattern_dummy",
      );
    });

    it("returns null for a compiled pattern tuple with unknown ref", () => {
      assert.isNull(RegexPatternRegistry.lookupByTerm(rePatternTuple(ref1)));
    });

    it("returns null for a tuple with another tag", () => {
      const term = Type.tuple([
        Type.atom("other_tag"),
        Type.integer(0),
        Type.integer(0),
        Type.integer(0),
        ref1,
      ]);

      assert.isNull(RegexPatternRegistry.lookupByTerm(term));
    });

    it("returns null for a tuple with another arity", () => {
      const term = Type.tuple([Type.atom("re_pattern"), ref1]);

      assert.isNull(RegexPatternRegistry.lookupByTerm(term));
    });

    it("returns null for a non-tuple term", () => {
      assert.isNull(RegexPatternRegistry.lookupByTerm(Type.atom("abc")));
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

  describe("putImport()", () => {
    it("overwrites what was stored under the same key", () => {
      RegexPatternRegistry.putImport("key_dummy", "imported_dummy_1");
      RegexPatternRegistry.putImport("key_dummy", "imported_dummy_2");

      assert.equal(RegexPatternRegistry.imports.size, 1);

      assert.equal(
        RegexPatternRegistry.getImport("key_dummy"),
        "imported_dummy_2",
      );
    });
  });
});

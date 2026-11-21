"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import RegexOffsetMap from "../../../../assets/js/erts/regex/regex_offset_map.mjs";

defineRuntimeGlobals();

// a: 1 byte / 1 UTF-16 unit, é: 2 bytes / 1 unit, €: 3 bytes / 1 unit, 😀: 4 bytes / 2 units
const text = "aé€😀";

// One 1-byte char, then 100 surrogate pairs, so checkpoint 1 (index 64) falls
// inside the pair at indices 63-64
const astralText = "a" + "😀".repeat(100);

describe("RegexOffsetMap", () => {
  describe("byteLength()", () => {
    it("returns the given byte length", () => {
      assert.equal(new RegexOffsetMap(text, 10).byteLength(), 10);
    });

    it("computes the byte length when unknown", () => {
      assert.equal(new RegexOffsetMap(text, null).byteLength(), 10);
    });

    it("computes the byte length of ASCII text when unknown", () => {
      assert.equal(new RegexOffsetMap("abc", null).byteLength(), 3);
    });

    it("returns 0 for empty text", () => {
      assert.equal(new RegexOffsetMap("", null).byteLength(), 0);
    });
  });

  describe("toByteOffset()", () => {
    it("returns 0 for index 0", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(0), 0);
    });

    it("converts index after 1-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(1), 1);
    });

    it("converts index after 2-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(2), 3);
    });

    it("converts index after 3-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(3), 6);
    });

    it("converts index after 4-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(5), 10);
    });

    it("converts index inside a surrogate pair to the offset after the pair", () => {
      assert.equal(new RegexOffsetMap(text, 10).toByteOffset(4), 10);
    });

    it("returns 0 for empty text", () => {
      assert.equal(new RegexOffsetMap("", 0).toByteOffset(0), 0);
    });

    it("converts index of ASCII text", () => {
      assert.equal(new RegexOffsetMap("abc", 3).toByteOffset(2), 2);
    });

    it("converts index before an already converted one", () => {
      const offsetMap = new RegexOffsetMap(text, 10);

      assert.equal(offsetMap.toByteOffset(5), 10);
      assert.equal(offsetMap.toByteOffset(2), 3);
    });

    it("converts index after an already converted one", () => {
      const offsetMap = new RegexOffsetMap(text, 10);

      assert.equal(offsetMap.toByteOffset(1), 1);
      assert.equal(offsetMap.toByteOffset(5), 10);
    });

    it("converts the same index twice", () => {
      const offsetMap = new RegexOffsetMap(text, 10);

      assert.equal(offsetMap.toByteOffset(3), 6);
      assert.equal(offsetMap.toByteOffset(3), 6);
    });

    it("converts indices past several checkpoints, in any order", () => {
      const offsetMap = new RegexOffsetMap("é".repeat(300), 600);

      assert.equal(offsetMap.toByteOffset(250), 500);
      assert.equal(offsetMap.toByteOffset(10), 20);
      assert.equal(offsetMap.toByteOffset(128), 256);
      assert.equal(offsetMap.toByteOffset(300), 600);
    });

    it("converts the index of a checkpoint inside a surrogate pair", () => {
      const offsetMap = new RegexOffsetMap(astralText, 401);

      assert.equal(offsetMap.toByteOffset(200), 401);
      assert.equal(offsetMap.toByteOffset(64), 129);
      assert.equal(offsetMap.toByteOffset(63), 125);
      assert.equal(offsetMap.toByteOffset(65), 129);
    });
  });

  describe("toIndex()", () => {
    it("returns 0 for offset 0", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(0), 0);
    });

    it("converts offset after 1-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(1), 1);
    });

    it("converts offset after 2-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(3), 2);
    });

    it("converts offset after 3-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(6), 3);
    });

    it("converts offset after 4-byte code point", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(10), 5);
    });

    it("converts offset inside a character to the index after it", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(2), 2);
    });

    it("clamps offset past the end of text", () => {
      assert.equal(new RegexOffsetMap(text, 10).toIndex(11), 5);
    });

    it("returns 0 for empty text", () => {
      assert.equal(new RegexOffsetMap("", 0).toIndex(3), 0);
    });

    it("converts offset of ASCII text", () => {
      assert.equal(new RegexOffsetMap("abc", 3).toIndex(2), 2);
    });

    it("clamps offset past the end of ASCII text", () => {
      assert.equal(new RegexOffsetMap("abc", 3).toIndex(5), 3);
    });

    it("converts offsets past several checkpoints, in any order", () => {
      const offsetMap = new RegexOffsetMap("é".repeat(300), 600);

      assert.equal(offsetMap.toIndex(500), 250);
      assert.equal(offsetMap.toIndex(20), 10);
      assert.equal(offsetMap.toIndex(257), 129);
      assert.equal(offsetMap.toIndex(600), 300);
    });

    it("converts offsets around a checkpoint inside a surrogate pair", () => {
      const offsetMap = new RegexOffsetMap(astralText, 401);

      assert.equal(offsetMap.toIndex(401), 201);
      assert.equal(offsetMap.toIndex(129), 65);
      assert.equal(offsetMap.toIndex(126), 65);
      assert.equal(offsetMap.toIndex(125), 63);
    });

    it("converts offsets after converting indices", () => {
      const offsetMap = new RegexOffsetMap("é".repeat(300), 600);

      assert.equal(offsetMap.toByteOffset(200), 400);
      assert.equal(offsetMap.toIndex(410), 205);
      assert.equal(offsetMap.toIndex(100), 50);
    });
  });
});

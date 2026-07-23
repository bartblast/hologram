"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import {codePointInRanges} from "../../../assets/js/regex/regex_char_sets.mjs";

defineGlobalErlangAndElixirModules();

const ranges = [
  [0x09, 0x0d],
  [0x20, 0x20],
];

describe("codePointInRanges()", () => {
  it("returns true inside a range", () => {
    assert.isTrue(codePointInRanges(ranges, 0x0b));
  });

  it("returns true at the inclusive lower bound", () => {
    assert.isTrue(codePointInRanges(ranges, 0x09));
  });

  it("returns true at the inclusive upper bound", () => {
    assert.isTrue(codePointInRanges(ranges, 0x0d));
  });

  it("returns true in a single-char range", () => {
    assert.isTrue(codePointInRanges(ranges, 0x20));
  });

  it("returns false between ranges", () => {
    assert.isFalse(codePointInRanges(ranges, 0x0e));
  });

  it("returns false before the first range", () => {
    assert.isFalse(codePointInRanges(ranges, 0x08));
  });

  it("returns false after the last range", () => {
    assert.isFalse(codePointInRanges(ranges, 0x21));
  });

  it("returns false for empty ranges", () => {
    assert.isFalse(codePointInRanges([], 0x41));
  });
});

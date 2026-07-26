"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexEngine from "../../../assets/js/regex/regex_engine.mjs";

defineGlobalErlangAndElixirModules();

const match = (source, subject, opts = {}, runOpts = {}) =>
  RegexEngine.match(RegexEngine.compile(source, opts), subject, runOpts);

describe("RegexEngine", () => {
  describe("byteOffsetToUtf16Index()", () => {
    it("converts a byte offset to a JS string index", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index("aé", 3), 2);
    });
  });

  describe("compile()", () => {
    it("routes translatable pattern to the native engine", () => {
      const compiled = RegexEngine.compile("a+b");

      assert.equal(compiled.strategy, "native");
      assert.instanceOf(compiled.regexp, RegExp);
    });

    it("routes exotic pattern to the interpreter", () => {
      const compiled = RegexEngine.compile("a\\Kb");

      assert.equal(compiled.strategy, "interpreted");
      assert.isNull(compiled.regexp);
    });

    it("returns the parse error as data on invalid pattern", () => {
      assert.deepEqual(RegexEngine.compile("a{2,1}"), {
        error: {message: "numbers out of order in {} quantifier", position: 5},
      });
    });
  });

  describe("match()", () => {
    it("matches on the native engine", () => {
      assert.deepEqual(match("b+c", "abbc"), {
        start: 1,
        end: 4,
        captures: [null],
      });
    });

    it("matches on the interpreter", () => {
      assert.deepEqual(match("b\\Kc", "abc"), {
        start: 2,
        end: 3,
        captures: [null],
      });
    });

    it("returns null without a match on the native engine", () => {
      assert.isNull(match("x", "abc"));
    });

    it("returns null without a match on the interpreter", () => {
      assert.isNull(match("x\\K", "abc"));
    });

    it("returns captures with PCRE numbering on the native engine", () => {
      assert.deepEqual(match("(a)(?>b)(c)", "abc"), {
        start: 0,
        end: 3,
        captures: [null, {start: 0, end: 1}, {start: 2, end: 3}],
      });
    });

    it("returns unset captures as null on the native engine", () => {
      assert.deepEqual(match("(a)|(b)", "b"), {
        start: 0,
        end: 1,
        captures: [null, null, {start: 0, end: 1}],
      });
    });

    it("returns captures on the interpreter", () => {
      assert.deepEqual(match("(a)(?1)\\K", "aa"), {
        start: 2,
        end: 2,
        captures: [null, {start: 0, end: 1}],
      });
    });

    it("honors compile options on the native engine", () => {
      assert.deepEqual(match("a", "A", {caseless: true}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("honors compile options on the interpreter", () => {
      assert.deepEqual(match("a\\Kb", "AB", {caseless: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("scans from the start position on the native engine", () => {
      assert.deepEqual(match("a", "aba", {}, {startPosition: 1}), {
        start: 2,
        end: 3,
        captures: [null],
      });
    });

    it("scans from the start position on the interpreter", () => {
      assert.deepEqual(match("a\\K", "aba", {}, {startPosition: 1}), {
        start: 3,
        end: 3,
        captures: [null],
      });
    });
  });

  describe("utf16IndexToByteOffset()", () => {
    it("converts a JS string index to a byte offset", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset("aé", 2), 3);
    });
  });
});

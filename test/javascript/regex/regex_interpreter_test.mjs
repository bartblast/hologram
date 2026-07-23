"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexInterpreter from "../../../assets/js/regex/regex_interpreter.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

const match = (source, subject, opts = {}) =>
  RegexInterpreter.match(RegexParser.parse(source, opts), subject, opts);

describe("RegexInterpreter", () => {
  describe("match()", () => {
    describe("alternation", () => {
      it("matches the first branch that succeeds", () => {
        assert.deepEqual(match("x|bc", "abcd"), {start: 1, end: 3});
      });

      it("prefers earlier branches at the same position", () => {
        assert.deepEqual(match("a|ab", "ab"), {start: 0, end: 1});
      });

      it("backtracks into later branches", () => {
        assert.deepEqual(match("ab|ac", "ac"), {start: 0, end: 2});
      });
    });

    describe("classes", () => {
      it("matches char in range", () => {
        assert.deepEqual(match("[b-d]", "ad"), {start: 1, end: 2});
      });

      it("matches char in negated class", () => {
        assert.deepEqual(match("[^a]", "aab"), {start: 2, end: 3});
      });

      it("returns null when no char is in class", () => {
        assert.isNull(match("[x-z]", "abc"));
      });

      it("matches caseless range members", () => {
        assert.deepEqual(match("[A-Z]", "x", {caseless: true}), {
          start: 0,
          end: 1,
        });
      });
    });

    describe("quantifiers", () => {
      it("matches greedily by default", () => {
        assert.deepEqual(match("a*", "aaa"), {start: 0, end: 3});
      });

      it("gives back greedy repetitions when needed", () => {
        assert.deepEqual(match("a*ab", "aaab"), {start: 0, end: 4});
      });

      it("matches lazily with minimal repetitions", () => {
        assert.deepEqual(match("a*?", "aaa"), {start: 0, end: 0});
      });

      it("grows lazy repetitions when needed", () => {
        assert.deepEqual(match("a*?b", "aaab"), {start: 0, end: 4});
      });

      it("matches exact count", () => {
        assert.deepEqual(match("a{2}", "aaa"), {start: 0, end: 2});
      });

      it("matches bounded range greedily", () => {
        assert.deepEqual(match("a{2,3}", "aaaa"), {start: 0, end: 3});
      });

      it("returns null below the minimum count", () => {
        assert.isNull(match("a{2,}", "a"));
      });

      it("matches optional item", () => {
        assert.deepEqual(match("ab?c", "ac"), {start: 0, end: 2});
      });

      it("matches quantified class", () => {
        assert.deepEqual(match("[ab]{2}", "xab"), {start: 1, end: 3});
      });

      it("swaps greediness with ungreedy option", () => {
        assert.deepEqual(match("a*", "aaa", {ungreedy: true}), {
          start: 0,
          end: 0,
        });
      });

      it("swaps laziness with ungreedy option", () => {
        assert.deepEqual(match("a*?", "aaa", {ungreedy: true}), {
          start: 0,
          end: 3,
        });
      });

      it("matches quantified astral char in unicode mode", () => {
        assert.deepEqual(match("😀+", "😀😀", {unicode: true}), {
          start: 0,
          end: 4,
        });
      });
    });

    describe("literals", () => {
      it("matches literal at a later position", () => {
        assert.deepEqual(match("b", "abc"), {start: 1, end: 2});
      });

      it("matches multi-char sequence", () => {
        assert.deepEqual(match("bc", "abcd"), {start: 1, end: 3});
      });

      it("returns null without a match", () => {
        assert.isNull(match("x", "abc"));
      });

      it("matches empty pattern at the start", () => {
        assert.deepEqual(match("", "a"), {start: 0, end: 0});
      });

      it("matches caseless literals", () => {
        assert.deepEqual(match("abc", "xABC", {caseless: true}), {
          start: 1,
          end: 4,
        });
      });

      it("matches non-ASCII literal in unicode mode", () => {
        assert.deepEqual(match("é", "xé", {unicode: true}), {
          start: 1,
          end: 2,
        });
      });

      it("matches astral literal as one char in unicode mode", () => {
        assert.deepEqual(match("😀", "a😀", {unicode: true}), {
          start: 1,
          end: 3,
        });
      });
    });
  });
});

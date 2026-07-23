"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexInterpreter from "../../../assets/js/regex/regex_interpreter.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

const match = (source, subject, opts = {}) => {
  const result = matchFull(source, subject, opts);

  return result === null ? null : {start: result.start, end: result.end};
};

const matchFull = (source, subject, opts = {}) =>
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

    describe("atomic matching", () => {
      it("does not backtrack into atomic group", () => {
        assert.isNull(match("(?>a+)a", "aaa"));
      });

      it("matches atomic group and continues", () => {
        assert.deepEqual(match("(?>a+)b", "aab"), {start: 0, end: 3});
      });

      it("rolls back captures locked inside a failed atomic group", () => {
        assert.deepEqual(matchFull("(?>(a))x|([a-z])y", "ay"), {
          start: 0,
          end: 2,
          captures: [null, null, {start: 0, end: 1}],
        });
      });

      it("does not give back possessive repetitions", () => {
        assert.isNull(match("a*+a", "aaa"));
      });

      it("matches possessive quantifier and continues", () => {
        assert.deepEqual(match("a*+b", "aab"), {start: 0, end: 3});
      });
    });

    describe("captures", () => {
      it("captures sequential groups", () => {
        assert.deepEqual(matchFull("(a)(b)", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 0, end: 1}, {start: 1, end: 2}],
        });
      });

      it("captures nested groups", () => {
        assert.deepEqual(matchFull("((a)b)", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 0, end: 2}, {start: 0, end: 1}],
        });
      });

      it("leaves non-participating group unset", () => {
        assert.deepEqual(matchFull("(a)|(b)", "b"), {
          start: 0,
          end: 1,
          captures: [null, null, {start: 0, end: 1}],
        });
      });

      it("leaves skipped optional group unset", () => {
        assert.deepEqual(matchFull("(a)?b", "b"), {
          start: 0,
          end: 1,
          captures: [null, null],
        });
      });

      it("keeps the last iteration of a quantified group", () => {
        assert.deepEqual(matchFull("([ab])+", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 1, end: 2}],
        });
      });

      it("restores captures abandoned by backtracking", () => {
        assert.deepEqual(matchFull("(a)b|ac", "ac"), {
          start: 0,
          end: 2,
          captures: [null, null],
        });
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

    describe("groups and options", () => {
      it("matches quantified non-capturing group", () => {
        assert.deepEqual(match("(?:ab)+c", "ababc"), {start: 0, end: 5});
      });

      it("stops empty repetitions of a group", () => {
        assert.deepEqual(match("(?:a?)*b", "b"), {start: 0, end: 1});
      });

      it("applies caseless option group within its scope", () => {
        assert.deepEqual(match("(?i:a)b", "Ab"), {start: 0, end: 2});
      });

      it("ends caseless option group scope at its close", () => {
        assert.isNull(match("(?i:a)b", "AB"));
      });

      it("applies inline option setting to the rest of the group", () => {
        assert.deepEqual(match("a(?i)b", "aB"), {start: 0, end: 2});
      });

      it("leaks inline option setting into subsequent branches", () => {
        assert.deepEqual(match("a(?i)b|c", "C"), {start: 0, end: 1});
      });

      it("applies scoped ungreedy option", () => {
        assert.deepEqual(match("(?U:a*)", "aaa"), {start: 0, end: 0});
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

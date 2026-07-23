"use strict";

import {
  assert,
  assertRegexParseError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

describe("RegexParser", () => {
  describe("parse()", () => {
    describe("anchors", () => {
      it("parses ^ as line start", () => {
        assert.deepEqual(RegexParser.parse("^"), {
          type: "anchor",
          kind: "lineStart",
        });
      });

      it("parses $ as line end", () => {
        assert.deepEqual(RegexParser.parse("$"), {
          type: "anchor",
          kind: "lineEnd",
        });
      });

      it("parses \\A as subject start", () => {
        assert.deepEqual(RegexParser.parse("\\A"), {
          type: "anchor",
          kind: "subjectStart",
        });
      });

      it("parses \\z as subject end", () => {
        assert.deepEqual(RegexParser.parse("\\z"), {
          type: "anchor",
          kind: "subjectEnd",
        });
      });

      it("parses \\Z as subject end before final newline", () => {
        assert.deepEqual(RegexParser.parse("\\Z"), {
          type: "anchor",
          kind: "subjectEndBeforeFinalNewline",
        });
      });

      it("parses \\b as word boundary", () => {
        assert.deepEqual(RegexParser.parse("\\b"), {
          type: "anchor",
          kind: "wordBoundary",
        });
      });

      it("parses \\B as non-word boundary", () => {
        assert.deepEqual(RegexParser.parse("\\B"), {
          type: "anchor",
          kind: "nonWordBoundary",
        });
      });

      it("parses \\G as match start", () => {
        assert.deepEqual(RegexParser.parse("\\G"), {
          type: "anchor",
          kind: "matchStart",
        });
      });

      it("parses anchors around literals", () => {
        assert.deepEqual(RegexParser.parse("^a$"), {
          type: "concatenation",
          items: [
            {type: "anchor", kind: "lineStart"},
            {type: "literal", codePoint: 97},
            {type: "anchor", kind: "lineEnd"},
          ],
        });
      });

      it("raises when quantifier follows ^ anchor", () => {
        assertRegexParseError(
          "^*",
          "quantifier does not follow a repeatable item",
          2,
        );
      });

      it("raises when quantifier follows escape anchor", () => {
        assertRegexParseError(
          "\\A*",
          "quantifier does not follow a repeatable item",
          3,
        );
      });
    });

    describe("alternation", () => {
      it("parses two branches", () => {
        assert.deepEqual(RegexParser.parse("a|b"), {
          type: "alternation",
          branches: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses three branches as a flat list", () => {
        assert.deepEqual(RegexParser.parse("a|b|c"), {
          type: "alternation",
          branches: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
            {type: "literal", codePoint: 99},
          ],
        });
      });

      it("parses branches with multiple characters", () => {
        assert.deepEqual(RegexParser.parse("ab|cd"), {
          type: "alternation",
          branches: [
            {
              type: "concatenation",
              items: [
                {type: "literal", codePoint: 97},
                {type: "literal", codePoint: 98},
              ],
            },
            {
              type: "concatenation",
              items: [
                {type: "literal", codePoint: 99},
                {type: "literal", codePoint: 100},
              ],
            },
          ],
        });
      });

      it("parses empty leading branch", () => {
        assert.deepEqual(RegexParser.parse("|a"), {
          type: "alternation",
          branches: [
            {type: "concatenation", items: []},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses empty trailing branch", () => {
        assert.deepEqual(RegexParser.parse("a|"), {
          type: "alternation",
          branches: [
            {type: "literal", codePoint: 97},
            {type: "concatenation", items: []},
          ],
        });
      });
    });

    describe("character classes", () => {
      it("parses class with single characters", () => {
        assert.deepEqual(RegexParser.parse("[abc]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
            {type: "literal", codePoint: 99},
          ],
        });
      });

      it("parses negated class", () => {
        assert.deepEqual(RegexParser.parse("[^ab]"), {
          type: "class",
          negated: true,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses range", () => {
        assert.deepEqual(RegexParser.parse("[a-z]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 97, to: 122}],
        });
      });

      it("parses range mixed with single characters", () => {
        assert.deepEqual(RegexParser.parse("[a-z0]"), {
          type: "class",
          negated: false,
          items: [
            {type: "range", from: 97, to: 122},
            {type: "literal", codePoint: 48},
          ],
        });
      });

      it("parses non-ASCII BMP range", () => {
        assert.deepEqual(RegexParser.parse("[à-ü]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 224, to: 252}],
        });
      });

      it("parses astral range", () => {
        assert.deepEqual(RegexParser.parse("[😀-😂]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 128512, to: 128514}],
        });
      });

      it("parses leading - as literal", () => {
        assert.deepEqual(RegexParser.parse("[-a]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 45},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses trailing - as literal", () => {
        assert.deepEqual(RegexParser.parse("[a-]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 45},
          ],
        });
      });

      it("parses - after range as literal", () => {
        assert.deepEqual(RegexParser.parse("[a-z-0]"), {
          type: "class",
          negated: false,
          items: [
            {type: "range", from: 97, to: 122},
            {type: "literal", codePoint: 45},
            {type: "literal", codePoint: 48},
          ],
        });
      });

      it("parses leading ] as literal", () => {
        assert.deepEqual(RegexParser.parse("[]a]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 93},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses leading ] in negated class as literal", () => {
        assert.deepEqual(RegexParser.parse("[^]a]"), {
          type: "class",
          negated: true,
          items: [
            {type: "literal", codePoint: 93},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses leading ] as range start", () => {
        assert.deepEqual(RegexParser.parse("[]-a]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 93, to: 97}],
        });
      });

      it("parses ^ not in first position as literal", () => {
        assert.deepEqual(RegexParser.parse("[a^]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 94},
          ],
        });
      });

      it("parses [ as literal", () => {
        assert.deepEqual(RegexParser.parse("[[]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 91}],
        });
      });

      it("parses quantifier metacharacters as literals", () => {
        assert.deepEqual(RegexParser.parse("[*+]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 42},
            {type: "literal", codePoint: 43},
          ],
        });
      });

      it("parses anchor and dot metacharacters as literals", () => {
        assert.deepEqual(RegexParser.parse("[.$^]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 46},
            {type: "literal", codePoint: 36},
            {type: "literal", codePoint: 94},
          ],
        });
      });

      it("parses quantified class", () => {
        assert.deepEqual(RegexParser.parse("[ab]*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {
            type: "class",
            negated: false,
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("parses POSIX class", () => {
        assert.deepEqual(RegexParser.parse("[[:alpha:]]"), {
          type: "class",
          negated: false,
          items: [{type: "posixClass", name: "alpha", negated: false}],
        });
      });

      it("parses negated POSIX class", () => {
        assert.deepEqual(RegexParser.parse("[[:^lower:]]"), {
          type: "class",
          negated: false,
          items: [{type: "posixClass", name: "lower", negated: true}],
        });
      });

      it("parses multiple POSIX classes", () => {
        assert.deepEqual(RegexParser.parse("[[:alpha:][:digit:]]"), {
          type: "class",
          negated: false,
          items: [
            {type: "posixClass", name: "alpha", negated: false},
            {type: "posixClass", name: "digit", negated: false},
          ],
        });
      });

      it("parses [ without POSIX shape as literal", () => {
        assert.deepEqual(RegexParser.parse("[[:a]]"), {
          type: "concatenation",
          items: [
            {
              type: "class",
              negated: false,
              items: [
                {type: "literal", codePoint: 91},
                {type: "literal", codePoint: 58},
                {type: "literal", codePoint: 97},
              ],
            },
            {type: "literal", codePoint: 93},
          ],
        });
      });

      it("raises on unterminated class", () => {
        assertRegexParseError(
          "[abc",
          "missing terminating ] for character class",
          4,
        );
      });

      it("raises on class closed only by literal ]", () => {
        assertRegexParseError(
          "[]",
          "missing terminating ] for character class",
          2,
        );
      });

      it("raises on range out of order", () => {
        assertRegexParseError(
          "[z-a]",
          "range out of order in character class",
          4,
        );
      });

      it("raises on unknown POSIX class name", () => {
        assertRegexParseError("[[:foo:]]", "unknown POSIX class name", 8);
      });

      it("raises on POSIX class used outside class", () => {
        assertRegexParseError(
          "[:alpha:]",
          "POSIX named classes are supported only within a class",
          9,
        );
      });

      it("raises on POSIX class as range endpoint", () => {
        assertRegexParseError(
          "[a-[:digit:]]",
          "invalid range in character class",
          12,
        );
      });
    });

    describe("concatenation", () => {
      it("parses two characters", () => {
        assert.deepEqual(RegexParser.parse("ab"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses three characters as a flat list", () => {
        assert.deepEqual(RegexParser.parse("abc"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
            {type: "literal", codePoint: 99},
          ],
        });
      });
    });

    describe("dot", () => {
      it("parses . as dot", () => {
        assert.deepEqual(RegexParser.parse("."), {type: "dot"});
      });

      it("parses quantified dot", () => {
        assert.deepEqual(RegexParser.parse(".*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "dot"},
        });
      });
    });

    describe("empty pattern", () => {
      it("parses to empty concatenation", () => {
        assert.deepEqual(RegexParser.parse(""), {
          type: "concatenation",
          items: [],
        });
      });
    });

    describe("escapes", () => {
      it("parses \\N as not-newline", () => {
        assert.deepEqual(RegexParser.parse("\\N"), {type: "notNewline"});
      });

      it("parses quantified \\N", () => {
        assert.deepEqual(RegexParser.parse("\\N*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "notNewline"},
        });
      });

      it("raises on \\ at end of pattern", () => {
        assertRegexParseError("a\\", "\\ at end of pattern", 2);
      });
    });

    describe("literal", () => {
      it("parses ASCII character", () => {
        assert.deepEqual(RegexParser.parse("a"), {
          type: "literal",
          codePoint: 97,
        });
      });

      it("parses non-ASCII BMP character", () => {
        assert.deepEqual(RegexParser.parse("é"), {
          type: "literal",
          codePoint: 233,
        });
      });

      it("parses astral character as a single literal", () => {
        assert.deepEqual(RegexParser.parse("😀"), {
          type: "literal",
          codePoint: 128512,
        });
      });
    });

    describe("quantifiers", () => {
      it("parses * as 0 to unbounded", () => {
        assert.deepEqual(RegexParser.parse("a*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses + as 1 to unbounded", () => {
        assert.deepEqual(RegexParser.parse("a+"), {
          type: "quantifier",
          min: 1,
          max: null,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses ? as 0 to 1", () => {
        assert.deepEqual(RegexParser.parse("a?"), {
          type: "quantifier",
          min: 0,
          max: 1,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses {n} as exact count", () => {
        assert.deepEqual(RegexParser.parse("a{3}"), {
          type: "quantifier",
          min: 3,
          max: 3,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses {n,} as n to unbounded", () => {
        assert.deepEqual(RegexParser.parse("a{2,}"), {
          type: "quantifier",
          min: 2,
          max: null,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses {n,m} as range", () => {
        assert.deepEqual(RegexParser.parse("a{2,5}"), {
          type: "quantifier",
          min: 2,
          max: 5,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses {,m} as 0 to m", () => {
        assert.deepEqual(RegexParser.parse("a{,5}"), {
          type: "quantifier",
          min: 0,
          max: 5,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses lazy mode", () => {
        assert.deepEqual(RegexParser.parse("a*?"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "lazy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses possessive mode", () => {
        assert.deepEqual(RegexParser.parse("a++"), {
          type: "quantifier",
          min: 1,
          max: null,
          mode: "possessive",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses lazy mode on {} quantifier", () => {
        assert.deepEqual(RegexParser.parse("a{2,5}?"), {
          type: "quantifier",
          min: 2,
          max: 5,
          mode: "lazy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses possessive mode on {} quantifier", () => {
        assert.deepEqual(RegexParser.parse("a{2,5}+"), {
          type: "quantifier",
          min: 2,
          max: 5,
          mode: "possessive",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("binds to the last atom only", () => {
        assert.deepEqual(RegexParser.parse("ab*"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {
              type: "quantifier",
              min: 0,
              max: null,
              mode: "greedy",
              item: {type: "literal", codePoint: 98},
            },
          ],
        });
      });

      it("quantifies astral character", () => {
        assert.deepEqual(RegexParser.parse("😀*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "literal", codePoint: 128512},
        });
      });

      it("accepts maximum repetition count", () => {
        assert.deepEqual(RegexParser.parse("a{65535}"), {
          type: "quantifier",
          min: 65535,
          max: 65535,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("parses { without bounds as literal", () => {
        assert.deepEqual(RegexParser.parse("a{"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 123},
          ],
        });
      });

      it("parses incomplete bounds as literals", () => {
        assert.deepEqual(RegexParser.parse("a{2,"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 123},
            {type: "literal", codePoint: 50},
            {type: "literal", codePoint: 44},
          ],
        });
      });

      it("parses unmatched } as literal", () => {
        assert.deepEqual(RegexParser.parse("a}"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 125},
          ],
        });
      });

      it("raises when quantifier has nothing to repeat", () => {
        assertRegexParseError(
          "*",
          "quantifier does not follow a repeatable item",
          1,
        );
      });

      it("raises when quantifier follows quantifier", () => {
        assertRegexParseError(
          "a**",
          "quantifier does not follow a repeatable item",
          3,
        );
      });

      it("raises when {} quantifier has nothing to repeat", () => {
        assertRegexParseError(
          "{2}",
          "quantifier does not follow a repeatable item",
          3,
        );
      });

      it("raises when numbers are out of order", () => {
        assertRegexParseError(
          "a{2,1}",
          "numbers out of order in {} quantifier",
          5,
        );
      });

      it("raises when number is too big", () => {
        assertRegexParseError("a{65536}", "number too big in {} quantifier", 7);
      });
    });

    it("raises on unsupported construct", () => {
      assertRegexParseError("a(", "unsupported pattern construct: (", 1);
    });
  });
});

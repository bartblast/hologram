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

    describe("backreferences", () => {
      it("parses single-digit backreference", () => {
        assert.deepEqual(RegexParser.parse("(a)\\1"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: 1, name: null},
          ],
        });
      });

      it("parses forward reference", () => {
        assert.deepEqual(RegexParser.parse("\\2(a)(b)"), {
          type: "concatenation",
          items: [
            {type: "backreference", number: 2, name: null},
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "group",
              number: 2,
              name: null,
              content: {type: "literal", codePoint: 98},
            },
          ],
        });
      });

      it("parses multi-digit backreference when the group exists", () => {
        const groups = [..."abcdefghijkl"].map((char, index) => ({
          type: "group",
          number: index + 1,
          name: null,
          content: {type: "literal", codePoint: char.codePointAt(0)},
        }));

        assert.deepEqual(
          RegexParser.parse("(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)\\12"),
          {
            type: "concatenation",
            items: [...groups, {type: "backreference", number: 12, name: null}],
          },
        );
      });

      it("parses multi-digit escape as octal when the group doesn't exist", () => {
        assert.deepEqual(RegexParser.parse("\\12"), {
          type: "literal",
          codePoint: 10,
        });
      });

      it("stops octal fallback at non-octal digit", () => {
        assert.deepEqual(RegexParser.parse("\\19"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 1},
            {type: "literal", codePoint: 57},
          ],
        });
      });

      it("binds quantifier to the literal digit after octal fallback", () => {
        assert.deepEqual(RegexParser.parse("\\19*"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 1},
            {
              type: "quantifier",
              min: 0,
              max: null,
              mode: "greedy",
              item: {type: "literal", codePoint: 57},
            },
          ],
        });
      });

      it("parses octal fallback above \\377 in unicode mode", () => {
        assert.deepEqual(RegexParser.parse("\\777", {unicode: true}), {
          type: "literal",
          codePoint: 511,
        });
      });

      it("raises on single-digit reference to non-existent group", () => {
        assertRegexParseError("\\1", "reference to non-existent subpattern", 2);
      });

      it("raises on multi-digit reference starting with 8 or 9", () => {
        assertRegexParseError(
          "\\89",
          "reference to non-existent subpattern",
          3,
        );
      });

      it("raises on octal fallback above \\377 in 8-bit mode", () => {
        assertRegexParseError(
          "\\777",
          "octal value is greater than \\377 in 8-bit non-UTF-8 mode",
          4,
        );
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

      it("parses escaped characters", () => {
        assert.deepEqual(RegexParser.parse("[\\n\\t]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 10},
            {type: "literal", codePoint: 9},
          ],
        });
      });

      it("parses \\b as backspace", () => {
        assert.deepEqual(RegexParser.parse("[\\b]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 8}],
        });
      });

      it("parses hex escapes", () => {
        assert.deepEqual(RegexParser.parse("[\\x41]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 65}],
        });
      });

      it("parses octal escapes", () => {
        assert.deepEqual(RegexParser.parse("[\\101]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 65}],
        });
      });

      it("parses octal escapes above \\377 in unicode mode", () => {
        assert.deepEqual(RegexParser.parse("[\\777]", {unicode: true}), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 511}],
        });
      });

      it("parses \\8 and \\9 as literal digits", () => {
        assert.deepEqual(RegexParser.parse("[\\8\\9]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 56},
            {type: "literal", codePoint: 57},
          ],
        });
      });

      it("parses \\g and \\k as literal letters", () => {
        assert.deepEqual(RegexParser.parse("[\\g\\k]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 103},
            {type: "literal", codePoint: 107},
          ],
        });
      });

      it("parses escaped dash as literal", () => {
        assert.deepEqual(RegexParser.parse("[\\-]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 45}],
        });
      });

      it("parses range with escaped endpoints", () => {
        assert.deepEqual(RegexParser.parse("[\\x00-\\x1f]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 0, to: 31}],
        });
      });

      it("parses shorthand escapes", () => {
        assert.deepEqual(RegexParser.parse("[\\d\\W]"), {
          type: "class",
          negated: false,
          items: [
            {type: "shorthand", letter: "d", negated: false},
            {type: "shorthand", letter: "w", negated: true},
          ],
        });
      });

      it("parses shorthand in negated class", () => {
        assert.deepEqual(RegexParser.parse("[^\\s]"), {
          type: "class",
          negated: true,
          items: [{type: "shorthand", letter: "s", negated: false}],
        });
      });

      it("parses - after shorthand before ] as literal", () => {
        assert.deepEqual(RegexParser.parse("[\\s-]"), {
          type: "class",
          negated: false,
          items: [
            {type: "shorthand", letter: "s", negated: false},
            {type: "literal", codePoint: 45},
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

      it("raises on \\N in class", () => {
        assertRegexParseError("[\\N]", "\\N is not supported in a class", 3);
      });

      it("raises on \\R in class", () => {
        assertRegexParseError(
          "[\\R]",
          "escape sequence is invalid in character class",
          3,
        );
      });

      it("raises on octal escape above \\377 in 8-bit mode", () => {
        assertRegexParseError(
          "[\\777]",
          "octal value is greater than \\377 in 8-bit non-UTF-8 mode",
          5,
        );
      });

      it("raises on unrecognized escape in class", () => {
        assertRegexParseError("[\\j]", "unrecognized character follows \\", 3);
      });

      it("raises on shorthand as range start", () => {
        assertRegexParseError("[\\d-a]", "invalid range in character class", 4);
      });

      it("raises on shorthand as range endpoint", () => {
        assertRegexParseError("[a-\\d]", "invalid range in character class", 5);
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

      it("parses \\N{U+hhhh} in unicode mode", () => {
        assert.deepEqual(RegexParser.parse("\\N{U+41}", {unicode: true}), {
          type: "literal",
          codePoint: 65,
        });
      });

      it("parses simple character escapes", () => {
        assert.deepEqual(RegexParser.parse("\\a\\e\\f\\n\\r\\t"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 7},
            {type: "literal", codePoint: 27},
            {type: "literal", codePoint: 12},
            {type: "literal", codePoint: 10},
            {type: "literal", codePoint: 13},
            {type: "literal", codePoint: 9},
          ],
        });
      });

      it("parses \\x with one hex digit", () => {
        assert.deepEqual(RegexParser.parse("\\x4"), {
          type: "literal",
          codePoint: 4,
        });
      });

      it("parses \\x with two hex digits", () => {
        assert.deepEqual(RegexParser.parse("\\x41"), {
          type: "literal",
          codePoint: 65,
        });
      });

      it("stops \\x after two hex digits", () => {
        assert.deepEqual(RegexParser.parse("\\x411"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 65},
            {type: "literal", codePoint: 49},
          ],
        });
      });

      it("parses \\x{hhh...}", () => {
        assert.deepEqual(RegexParser.parse("\\x{41}"), {
          type: "literal",
          codePoint: 65,
        });
      });

      it("parses \\x{hhh...} up to 0xff in 8-bit mode", () => {
        assert.deepEqual(RegexParser.parse("\\x{ff}"), {
          type: "literal",
          codePoint: 255,
        });
      });

      it("parses \\x{hhh...} beyond BMP in unicode mode", () => {
        assert.deepEqual(RegexParser.parse("\\x{1F600}", {unicode: true}), {
          type: "literal",
          codePoint: 128512,
        });
      });

      it("parses \\0 as NUL", () => {
        assert.deepEqual(RegexParser.parse("\\0"), {
          type: "literal",
          codePoint: 0,
        });
      });

      it("parses \\0 with two more octal digits", () => {
        assert.deepEqual(RegexParser.parse("\\012"), {
          type: "literal",
          codePoint: 10,
        });
      });

      it("stops \\0 octal after three digits", () => {
        assert.deepEqual(RegexParser.parse("\\0123"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 10},
            {type: "literal", codePoint: 51},
          ],
        });
      });

      it("parses \\o{ddd...}", () => {
        assert.deepEqual(RegexParser.parse("\\o{101}"), {
          type: "literal",
          codePoint: 65,
        });
      });

      it("parses \\c with uppercase letter", () => {
        assert.deepEqual(RegexParser.parse("\\cA"), {
          type: "literal",
          codePoint: 1,
        });
      });

      it("parses \\c with lowercase letter", () => {
        assert.deepEqual(RegexParser.parse("\\ca"), {
          type: "literal",
          codePoint: 1,
        });
      });

      it("parses \\c with punctuation character", () => {
        assert.deepEqual(RegexParser.parse("\\c["), {
          type: "literal",
          codePoint: 27,
        });
      });

      it("parses escaped metacharacter as literal", () => {
        assert.deepEqual(RegexParser.parse("\\."), {
          type: "literal",
          codePoint: 46,
        });
      });

      it("parses escaped backslash as literal", () => {
        assert.deepEqual(RegexParser.parse("\\\\"), {
          type: "literal",
          codePoint: 92,
        });
      });

      it("parses escaped non-alphanumeric non-ASCII as literal", () => {
        assert.deepEqual(RegexParser.parse("\\é"), {
          type: "literal",
          codePoint: 233,
        });
      });

      it("parses \\d as digit shorthand", () => {
        assert.deepEqual(RegexParser.parse("\\d"), {
          type: "shorthand",
          letter: "d",
          negated: false,
        });
      });

      it("parses \\D as negated digit shorthand", () => {
        assert.deepEqual(RegexParser.parse("\\D"), {
          type: "shorthand",
          letter: "d",
          negated: true,
        });
      });

      it("parses all shorthand letters", () => {
        assert.deepEqual(RegexParser.parse("\\s\\S\\w\\W\\h\\H\\v\\V"), {
          type: "concatenation",
          items: [
            {type: "shorthand", letter: "s", negated: false},
            {type: "shorthand", letter: "s", negated: true},
            {type: "shorthand", letter: "w", negated: false},
            {type: "shorthand", letter: "w", negated: true},
            {type: "shorthand", letter: "h", negated: false},
            {type: "shorthand", letter: "h", negated: true},
            {type: "shorthand", letter: "v", negated: false},
            {type: "shorthand", letter: "v", negated: true},
          ],
        });
      });

      it("parses quantified shorthand", () => {
        assert.deepEqual(RegexParser.parse("\\d+"), {
          type: "quantifier",
          min: 1,
          max: null,
          mode: "greedy",
          item: {type: "shorthand", letter: "d", negated: false},
        });
      });

      it("parses \\R as newline sequence", () => {
        assert.deepEqual(RegexParser.parse("\\R"), {type: "newlineSequence"});
      });

      it("parses quantified \\R", () => {
        assert.deepEqual(RegexParser.parse("\\R*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "newlineSequence"},
        });
      });

      it("raises on \\ at end of pattern", () => {
        assertRegexParseError("a\\", "\\ at end of pattern", 2);
      });

      it("raises on \\x without hex digits", () => {
        assertRegexParseError(
          "\\x",
          "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
          2,
        );
      });

      it("raises on empty \\x{}", () => {
        assertRegexParseError(
          "\\x{}",
          "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
          3,
        );
      });

      it("raises on non-hex character in \\x{}", () => {
        assertRegexParseError(
          "\\x{4g}",
          "non-hex character in \\x{} (closing brace missing?)",
          5,
        );
      });

      it("raises on \\x{} without closing brace", () => {
        assertRegexParseError(
          "\\x{41",
          "non-hex character in \\x{} (closing brace missing?)",
          6,
        );
      });

      it("raises on \\x{} value too large for 8-bit mode", () => {
        assertRegexParseError(
          "\\x{100}",
          "character code point value in \\x{} or \\o{} is too large",
          6,
        );
      });

      it("raises on \\x{} value too large for unicode mode", () => {
        assertRegexParseError(
          "\\x{110000}",
          "character code point value in \\x{} or \\o{} is too large",
          9,
          {unicode: true},
        );
      });

      it("raises on \\x{} surrogate value in unicode mode", () => {
        assertRegexParseError(
          "\\x{d800}",
          "disallowed Unicode code point (>= 0xd800 && <= 0xdfff)",
          7,
          {unicode: true},
        );
      });

      it("raises on \\o without opening brace", () => {
        assertRegexParseError("\\o", "missing opening brace after \\o", 2);
      });

      it("raises on empty \\o{}", () => {
        assertRegexParseError(
          "\\o{}",
          "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
          3,
        );
      });

      it("raises on non-octal character in \\o{}", () => {
        assertRegexParseError(
          "\\o{8}",
          "non-octal character in \\o{} (closing brace missing?)",
          4,
        );
      });

      it("raises on \\o{} value too large for 8-bit mode", () => {
        assertRegexParseError(
          "\\o{400}",
          "character code point value in \\x{} or \\o{} is too large",
          6,
        );
      });

      it("raises on \\c at end of pattern", () => {
        assertRegexParseError("\\c", "\\c at end of pattern", 2);
      });

      it("raises on \\c followed by non-printable ASCII", () => {
        assertRegexParseError(
          "\\cé",
          "\\c must be followed by a printable ASCII character",
          3,
        );
      });

      it("raises on unrecognized escape", () => {
        assertRegexParseError("\\j", "unrecognized character follows \\", 2);
      });

      it("raises on escape unsupported by PCRE2", () => {
        assertRegexParseError(
          "\\u",
          "PCRE2 does not support \\F, \\L, \\l, \\N{name}, \\U, or \\u",
          2,
        );
      });

      it("raises on \\N{name} form", () => {
        assertRegexParseError(
          "\\N{x}",
          "PCRE2 does not support \\F, \\L, \\l, \\N{name}, \\U, or \\u",
          3,
        );
      });

      it("raises on \\N{U+hhhh} in 8-bit mode", () => {
        assertRegexParseError(
          "\\N{U+41}",
          "\\N{U+dddd} is supported only in Unicode (UTF) mode",
          8,
        );
      });
    });

    describe("groups", () => {
      it("parses capturing group", () => {
        assert.deepEqual(RegexParser.parse("(a)"), {
          type: "group",
          number: 1,
          name: null,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("numbers groups by opening parenthesis order", () => {
        assert.deepEqual(RegexParser.parse("(a)(b)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "group",
              number: 2,
              name: null,
              content: {type: "literal", codePoint: 98},
            },
          ],
        });
      });

      it("numbers nested groups outside-in", () => {
        assert.deepEqual(RegexParser.parse("((a))"), {
          type: "group",
          number: 1,
          name: null,
          content: {
            type: "group",
            number: 2,
            name: null,
            content: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses alternation inside group", () => {
        assert.deepEqual(RegexParser.parse("(a|b)"), {
          type: "group",
          number: 1,
          name: null,
          content: {
            type: "alternation",
            branches: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("parses empty group", () => {
        assert.deepEqual(RegexParser.parse("()"), {
          type: "group",
          number: 1,
          name: null,
          content: {type: "concatenation", items: []},
        });
      });

      it("parses quantified group", () => {
        assert.deepEqual(RegexParser.parse("(ab)*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {
            type: "group",
            number: 1,
            name: null,
            content: {
              type: "concatenation",
              items: [
                {type: "literal", codePoint: 97},
                {type: "literal", codePoint: 98},
              ],
            },
          },
        });
      });

      it("parses non-capturing group", () => {
        assert.deepEqual(RegexParser.parse("(?:ab)"), {
          type: "nonCapturingGroup",
          content: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("skips non-capturing groups in numbering", () => {
        assert.deepEqual(RegexParser.parse("(?:a)(b)"), {
          type: "concatenation",
          items: [
            {
              type: "nonCapturingGroup",
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 98},
            },
          ],
        });
      });

      it("parses atomic group", () => {
        assert.deepEqual(RegexParser.parse("(?>a+)"), {
          type: "atomicGroup",
          content: {
            type: "quantifier",
            min: 1,
            max: null,
            mode: "greedy",
            item: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses named group with angle brackets", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)"), {
          type: "group",
          number: 1,
          name: "x",
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses named group with quotes", () => {
        assert.deepEqual(RegexParser.parse("(?'x'a)"), {
          type: "group",
          number: 1,
          name: "x",
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses named group with P prefix", () => {
        assert.deepEqual(RegexParser.parse("(?P<x>a)"), {
          type: "group",
          number: 1,
          name: "x",
          content: {type: "literal", codePoint: 97},
        });
      });

      it("numbers named and unnamed groups together", () => {
        assert.deepEqual(RegexParser.parse("(a)(?<x>b)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "group",
              number: 2,
              name: "x",
              content: {type: "literal", codePoint: 98},
            },
          ],
        });
      });

      it("allows duplicate names with dupnames option", () => {
        assert.deepEqual(
          RegexParser.parse("(?<x>a)(?<x>b)", {dupnames: true}),
          {
            type: "concatenation",
            items: [
              {
                type: "group",
                number: 1,
                name: "x",
                content: {type: "literal", codePoint: 97},
              },
              {
                type: "group",
                number: 2,
                name: "x",
                content: {type: "literal", codePoint: 98},
              },
            ],
          },
        );
      });

      it("makes plain groups non-capturing with noAutoCapture option", () => {
        assert.deepEqual(
          RegexParser.parse("(?<x>a)(b)", {noAutoCapture: true}),
          {
            type: "concatenation",
            items: [
              {
                type: "group",
                number: 1,
                name: "x",
                content: {type: "literal", codePoint: 97},
              },
              {
                type: "nonCapturingGroup",
                content: {type: "literal", codePoint: 98},
              },
            ],
          },
        );
      });

      it("raises on missing closing parenthesis", () => {
        assertRegexParseError("(a", "missing closing parenthesis", 2);
      });

      it("raises on unmatched closing parenthesis", () => {
        assertRegexParseError("a)b", "unmatched closing parenthesis", 2);
      });

      it("raises on unmatched closing parenthesis at pattern start", () => {
        assertRegexParseError(")", "unmatched closing parenthesis", 1);
      });

      it("raises on empty group name", () => {
        assertRegexParseError("(?<>a)", "subpattern name expected", 3);
      });

      it("raises on group name starting with digit", () => {
        assertRegexParseError(
          "(?<1a>x)",
          "subpattern name must start with a non-digit",
          4,
        );
      });

      it("raises on too long group name", () => {
        assertRegexParseError(
          `(?<${"a".repeat(129)}>x)`,
          "subpattern name is too long (maximum 128 code units)",
          132,
        );
      });

      it("raises on unterminated group name", () => {
        assertRegexParseError(
          "(?<ab)x",
          "syntax error in subpattern name (missing terminator?)",
          5,
        );
      });

      it("raises on duplicate group name", () => {
        assertRegexParseError(
          "(?<ab>x)(?<ab>y)",
          "two named subpatterns have the same name (PCRE2_DUPNAMES not set)",
          14,
        );
      });

      it("raises on unrecognized character after (?P", () => {
        assertRegexParseError("(?Px)", "unrecognized character after (?P", 4);
      });

      it("raises on unrecognized character after (?", () => {
        assertRegexParseError(
          "(?_x)",
          "unrecognized character after (? or (?-",
          3,
        );
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

    describe("lookarounds", () => {
      it("parses positive lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?=a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses negative lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?!a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses positive lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<=a)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses negative lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<!a)"), {
          type: "lookaround",
          direction: "behind",
          negated: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses capturing group inside lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?=(a))"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          content: {
            type: "group",
            number: 1,
            name: null,
            content: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses quantified lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?=a)*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {
            type: "lookaround",
            direction: "ahead",
            negated: false,
            content: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses bounded variable-length lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<=a{0,255})"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          content: {
            type: "quantifier",
            min: 0,
            max: 255,
            mode: "greedy",
            item: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses lookbehind with variable-length alternation", () => {
        assert.deepEqual(RegexParser.parse("(?<=(a|bc))"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          content: {
            type: "group",
            number: 1,
            name: null,
            content: {
              type: "alternation",
              branches: [
                {type: "literal", codePoint: 97},
                {
                  type: "concatenation",
                  items: [
                    {type: "literal", codePoint: 98},
                    {type: "literal", codePoint: 99},
                  ],
                },
              ],
            },
          },
        });
      });

      it("parses lookahead nested inside lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<=(?=a*)b)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          content: {
            type: "concatenation",
            items: [
              {
                type: "lookaround",
                direction: "ahead",
                negated: false,
                content: {
                  type: "quantifier",
                  min: 0,
                  max: null,
                  mode: "greedy",
                  item: {type: "literal", codePoint: 97},
                },
              },
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("raises on unbounded lookbehind", () => {
        assertRegexParseError(
          "(?<=a*)b",
          "length of lookbehind assertion is not limited",
          0,
        );
      });

      it("raises on unbounded lookbehind not at pattern start", () => {
        assertRegexParseError(
          "x(?<=a+)b",
          "length of lookbehind assertion is not limited",
          1,
        );
      });

      it("raises on unbounded negative lookbehind", () => {
        assertRegexParseError(
          "(?<!a*)b",
          "length of lookbehind assertion is not limited",
          0,
        );
      });

      it("raises on too long lookbehind branch", () => {
        assertRegexParseError(
          "(?<=a{0,256})b",
          "branch too long in variable-length lookbehind assertion",
          0,
        );
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
  });
});

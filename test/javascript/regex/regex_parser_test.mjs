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
    describe("alpha assertions", () => {
      it("parses (*atomic:...) as atomic group", () => {
        assert.deepEqual(RegexParser.parse("(*atomic:a+)b"), {
          type: "concatenation",
          items: [
            {
              type: "atomicGroup",
              content: {
                type: "quantifier",
                min: 1,
                max: null,
                mode: "greedy",
                item: {type: "literal", codePoint: 97},
              },
            },
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses (*pla:...) as positive lookahead", () => {
        assert.deepEqual(RegexParser.parse("(*pla:a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*positive_lookahead:...) as positive lookahead", () => {
        assert.deepEqual(RegexParser.parse("(*positive_lookahead:a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*nla:...) as negative lookahead", () => {
        assert.deepEqual(RegexParser.parse("(*nla:a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: true,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*plb:...) as positive lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(*plb:a)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*nlb:...) as negative lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(*nlb:a)"), {
          type: "lookaround",
          direction: "behind",
          negated: true,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*napla:...) as non-atomic positive lookahead", () => {
        assert.deepEqual(RegexParser.parse("(*napla:a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          atomic: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*naplb:...) as non-atomic positive lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(*naplb:a)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          atomic: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (?* as non-atomic positive lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?*a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          atomic: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (?<* as non-atomic positive lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<*a)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          atomic: false,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses (*sr:...) as script run", () => {
        assert.deepEqual(RegexParser.parse("(*sr:ab)"), {
          type: "scriptRun",
          atomic: false,
          content: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("parses (*asr:...) as atomic script run", () => {
        assert.deepEqual(RegexParser.parse("(*asr:ab)"), {
          type: "scriptRun",
          atomic: true,
          content: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("raises on unbounded alpha lookbehind", () => {
        assertRegexParseError(
          "(*plb:a*)b",
          "length of lookbehind assertion is not limited",
          2,
        );
      });

      it("raises on unknown alpha assertion name", () => {
        assertRegexParseError(
          "(*foo:a)",
          "(*alpha_assertion) not recognized",
          5,
        );
      });

      it("raises on alpha assertion without colon", () => {
        assertRegexParseError(
          "(*atomic)",
          "(*alpha_assertion) not recognized",
          9,
        );
      });
    });

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

      it("parses \\g with plain number", () => {
        assert.deepEqual(RegexParser.parse("(a)\\g1"), {
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

      it("parses \\g with braced number", () => {
        assert.deepEqual(RegexParser.parse("(a)\\g{1}"), {
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

      it("resolves \\g with negative relative number", () => {
        assert.deepEqual(RegexParser.parse("(a)(b)\\g{-1}"), {
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
            {type: "backreference", number: 2, name: null},
          ],
        });
      });

      it("resolves \\g with positive relative number", () => {
        assert.deepEqual(RegexParser.parse("\\g{+1}(a)"), {
          type: "concatenation",
          items: [
            {type: "backreference", number: 1, name: null},
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
          ],
        });
      });

      it("parses \\g with braced name", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)\\g{x}"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: null, name: "x"},
          ],
        });
      });

      it("parses \\k with angle-bracketed name", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)\\k<x>"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: null, name: "x"},
          ],
        });
      });

      it("parses \\k with quoted name", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)\\k'x'"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: null, name: "x"},
          ],
        });
      });

      it("parses \\k with braced name", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)\\k{x}"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: null, name: "x"},
          ],
        });
      });

      it("parses (?P=name) reference", () => {
        assert.deepEqual(RegexParser.parse("(?P<x>a)(?P=x)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "backreference", number: null, name: "x"},
          ],
        });
      });

      it("parses forward named reference", () => {
        assert.deepEqual(RegexParser.parse("\\k<x>(?<x>a)"), {
          type: "concatenation",
          items: [
            {type: "backreference", number: null, name: "x"},
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
          ],
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

      it("raises on \\g without reference", () => {
        assertRegexParseError(
          "\\g",
          "\\g is not followed by a braced, angle-bracketed, or quoted name/number or by a plain number",
          2,
        );
      });

      it("raises on \\g with empty braces", () => {
        assertRegexParseError("(a)\\g{}", "subpattern name expected", 6);
      });

      it("raises on \\g reference to non-existent group", () => {
        assertRegexParseError(
          "(a)\\g{2}",
          "reference to non-existent subpattern",
          8,
        );
      });

      it("raises on \\g relative reference before first group", () => {
        assertRegexParseError(
          "\\g{-1}",
          "reference to non-existent subpattern",
          2,
        );
      });

      it("raises on \\k without delimited name", () => {
        assertRegexParseError(
          "\\k",
          "\\k is not followed by a braced, angle-bracketed, or quoted name",
          2,
        );
      });

      it("raises on \\k reference to non-existent name", () => {
        assertRegexParseError(
          "(?<x>a)\\k<y>",
          "reference to non-existent subpattern",
          10,
        );
      });

      it("raises on (?P=) reference to non-existent name", () => {
        assertRegexParseError(
          "(?<x>a)(?P=y)",
          "reference to non-existent subpattern",
          11,
        );
      });

      it("raises on invalid character in \\k name", () => {
        assertRegexParseError(
          "(?<x>a)\\k<x*>",
          "syntax error in subpattern name (missing terminator?)",
          11,
        );
      });
    });

    describe("branch reset groups", () => {
      it("restarts group numbering in each branch", () => {
        assert.deepEqual(RegexParser.parse("(?|(a)|(b))"), {
          type: "branchResetGroup",
          content: {
            type: "alternation",
            branches: [
              {
                type: "group",
                number: 1,
                name: null,
                content: {type: "literal", codePoint: 97},
              },
              {
                type: "group",
                number: 1,
                name: null,
                content: {type: "literal", codePoint: 98},
              },
            ],
          },
        });
      });

      it("continues numbering after the widest branch", () => {
        assert.deepEqual(RegexParser.parse("(?|(a)(b)|(c))(d)"), {
          type: "concatenation",
          items: [
            {
              type: "branchResetGroup",
              content: {
                type: "alternation",
                branches: [
                  {
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
                  },
                  {
                    type: "group",
                    number: 1,
                    name: null,
                    content: {type: "literal", codePoint: 99},
                  },
                ],
              },
            },
            {
              type: "group",
              number: 3,
              name: null,
              content: {type: "literal", codePoint: 100},
            },
          ],
        });
      });

      it("parses single branch", () => {
        assert.deepEqual(RegexParser.parse("(?|(a))"), {
          type: "branchResetGroup",
          content: {
            type: "group",
            number: 1,
            name: null,
            content: {type: "literal", codePoint: 97},
          },
        });
      });

      it("allows duplicate names across branches", () => {
        assert.deepEqual(RegexParser.parse("(?|(?<x>a)|(?<x>b))"), {
          type: "branchResetGroup",
          content: {
            type: "alternation",
            branches: [
              {
                type: "group",
                number: 1,
                name: "x",
                content: {type: "literal", codePoint: 97},
              },
              {
                type: "group",
                number: 1,
                name: "x",
                content: {type: "literal", codePoint: 98},
              },
            ],
          },
        });
      });

      it("raises on duplicate names in the same branch", () => {
        assertRegexParseError(
          "(?|(?<x>a)(?<x>b))",
          "two named subpatterns have the same name (PCRE2_DUPNAMES not set)",
          15,
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

      it("parses quoted metacharacters as literal members", () => {
        assert.deepEqual(RegexParser.parse("[\\Qa-b\\E]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 45},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses quoted ] as literal member", () => {
        assert.deepEqual(RegexParser.parse("[\\Q]\\E]"), {
          type: "class",
          negated: false,
          items: [{type: "literal", codePoint: 93}],
        });
      });

      it("parses quoted backslash as literal member", () => {
        assert.deepEqual(RegexParser.parse("[\\Q\\d\\E]"), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 92},
            {type: "literal", codePoint: 100},
          ],
        });
      });

      it("parses range with quoted start", () => {
        assert.deepEqual(RegexParser.parse("[\\Qa\\E-z]"), {
          type: "class",
          negated: false,
          items: [{type: "range", from: 97, to: 122}],
        });
      });

      it("keeps quoted space literal in extended-more mode", () => {
        assert.deepEqual(RegexParser.parse("(?xx)[\\Q \\E]"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "xx", unset: ""},
            {
              type: "class",
              negated: false,
              items: [{type: "literal", codePoint: 32}],
            },
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

      it("raises on class unterminated inside quote", () => {
        assertRegexParseError(
          "[\\Qa",
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

    describe("comments", () => {
      it("skips comment", () => {
        assert.deepEqual(RegexParser.parse("a(?#c)b"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("skips empty comment", () => {
        assert.deepEqual(RegexParser.parse("a(?#)b"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("binds quantifier through comment to preceding item", () => {
        assert.deepEqual(RegexParser.parse("a(?#c)*"), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("raises on unterminated comment", () => {
        assertRegexParseError("a(?#bc", "missing ) after (?# comment", 6);
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

    describe("conditionals", () => {
      it("parses numeric condition", () => {
        assert.deepEqual(RegexParser.parse("(a)(?(1)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: 1, name: null},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses condition without no-branch", () => {
        assert.deepEqual(RegexParser.parse("(a)(?(1)b)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: 1, name: null},
              yes: {type: "literal", codePoint: 98},
              no: null,
            },
          ],
        });
      });

      it("resolves relative numeric condition", () => {
        assert.deepEqual(RegexParser.parse("(a)(?(-1)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: 1, name: null},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses angle-bracketed name condition", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)(?(<x>)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: null, name: "x"},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses bare name condition", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)(?(x)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: null, name: "x"},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses name starting with R as name condition", () => {
        assert.deepEqual(RegexParser.parse("(?<Rx>a)(?(Rx)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "Rx",
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "group", number: null, name: "Rx"},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses whole-pattern recursion condition", () => {
        assert.deepEqual(RegexParser.parse("(a)(?(R)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "recursion", number: null, name: null},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses numeric recursion condition", () => {
        assert.deepEqual(RegexParser.parse("(a)(b)(?(R2)c|d)"), {
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
            {
              type: "conditional",
              condition: {kind: "recursion", number: 2, name: null},
              yes: {type: "literal", codePoint: 99},
              no: {type: "literal", codePoint: 100},
            },
          ],
        });
      });

      it("parses named recursion condition", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)(?(R&x)b|c)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {
              type: "conditional",
              condition: {kind: "recursion", number: null, name: "x"},
              yes: {type: "literal", codePoint: 98},
              no: {type: "literal", codePoint: 99},
            },
          ],
        });
      });

      it("parses DEFINE condition", () => {
        assert.deepEqual(RegexParser.parse("(?(DEFINE)(?<x>a))(?&x)"), {
          type: "concatenation",
          items: [
            {
              type: "conditional",
              condition: {kind: "define"},
              yes: {
                type: "group",
                number: 1,
                name: "x",
                content: {type: "literal", codePoint: 97},
              },
              no: null,
            },
            {type: "subroutine", number: null, name: "x"},
          ],
        });
      });

      it("parses assertion condition", () => {
        assert.deepEqual(RegexParser.parse("(?(?=a)ab|cd)"), {
          type: "conditional",
          condition: {
            kind: "assertion",
            assertion: {
              type: "lookaround",
              direction: "ahead",
              negated: false,
              atomic: true,
              content: {type: "literal", codePoint: 97},
            },
          },
          yes: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
          no: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 99},
              {type: "literal", codePoint: 100},
            ],
          },
        });
      });

      it("parses VERSION condition with >=", () => {
        assert.deepEqual(RegexParser.parse("(?(VERSION>=10.4)a|b)"), {
          type: "conditional",
          condition: {kind: "version", gte: true, major: 10, minor: 4},
          yes: {type: "literal", codePoint: 97},
          no: {type: "literal", codePoint: 98},
        });
      });

      it("parses VERSION condition with =", () => {
        assert.deepEqual(RegexParser.parse("(?(VERSION=10.4)a|b)"), {
          type: "conditional",
          condition: {kind: "version", gte: false, major: 10, minor: 4},
          yes: {type: "literal", codePoint: 97},
          no: {type: "literal", codePoint: 98},
        });
      });

      it("parses VERSION condition without minor version", () => {
        assert.deepEqual(RegexParser.parse("(?(VERSION>=10)a)"), {
          type: "conditional",
          condition: {kind: "version", gte: true, major: 10, minor: 0},
          yes: {type: "literal", codePoint: 97},
          no: null,
        });
      });

      it("raises on more than two branches", () => {
        assertRegexParseError(
          "(?(1)a|b|c)(x)",
          "conditional subpattern contains more than two branches",
          0,
        );
      });

      it("raises on DEFINE with more than one branch", () => {
        assertRegexParseError(
          "(?(DEFINE)a|b)",
          "DEFINE subpattern contains more than one branch",
          3,
        );
      });

      it("raises on condition referencing non-existent group", () => {
        assertRegexParseError(
          "(?(2)a|b)(x)",
          "reference to non-existent subpattern",
          2,
        );
      });

      it("raises on relative condition referencing non-existent group", () => {
        assertRegexParseError(
          "^(a)(?(+1)b|c)$",
          "reference to non-existent subpattern",
          7,
        );
      });

      it("raises on condition referencing non-existent name", () => {
        assertRegexParseError(
          "(?<x>a)(?(y)b|c)",
          "reference to non-existent subpattern",
          10,
        );
      });

      it("raises on recursion condition referencing non-existent group", () => {
        assertRegexParseError(
          "(?(R99)a)(b)",
          "reference to non-existent subpattern",
          3,
        );
      });

      it("raises on junk after condition number", () => {
        assertRegexParseError(
          "(?(1x)a)(x)",
          "missing closing parenthesis for condition",
          4,
        );
      });

      it("raises on condition at end of pattern", () => {
        assertRegexParseError("(?(", "missing closing parenthesis", 3);
      });

      it("raises on unterminated bare name condition", () => {
        assertRegexParseError(
          "(?(x",
          "syntax error in subpattern name (missing terminator?)",
          4,
        );
      });

      it("raises on VERSION condition with invalid operator", () => {
        assertRegexParseError(
          "(?(VERSION>10)a)",
          "syntax error or number too big in (?(VERSION condition",
          11,
        );
      });

      it("raises on bare VERSION treated as name condition", () => {
        assertRegexParseError(
          "(?(VERSION)a)",
          "reference to non-existent subpattern",
          3,
        );
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

      it("parses \\K as match start reset", () => {
        assert.deepEqual(RegexParser.parse("a\\Kb"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "matchStartReset"},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("raises on \\ at end of pattern", () => {
        assertRegexParseError("a\\", "\\ at end of pattern", 2);
      });

      it("raises when quantifier follows \\K", () => {
        assertRegexParseError(
          "a\\K*",
          "quantifier does not follow a repeatable item",
          4,
        );
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

    describe("extended mode", () => {
      it("ignores whitespace", () => {
        assert.deepEqual(RegexParser.parse("a b", {extended: true}), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("skips # comment until end of line", () => {
        assert.deepEqual(RegexParser.parse("a # c\nb", {extended: true}), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("keeps escaped space literal", () => {
        assert.deepEqual(RegexParser.parse("a\\ b", {extended: true}), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 32},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("keeps space in class literal", () => {
        assert.deepEqual(RegexParser.parse("[a ]", {extended: true}), {
          type: "class",
          negated: false,
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 32},
          ],
        });
      });

      it("applies whitespace before quantifier", () => {
        assert.deepEqual(RegexParser.parse("a {2}", {extended: true}), {
          type: "quantifier",
          min: 2,
          max: 2,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("applies whitespace before quantifier mode suffix", () => {
        assert.deepEqual(RegexParser.parse("a * +", {extended: true}), {
          type: "quantifier",
          min: 0,
          max: null,
          mode: "possessive",
          item: {type: "literal", codePoint: 97},
        });
      });

      it("starts with inline x setting", () => {
        assert.deepEqual(RegexParser.parse("(?x)a b"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "x", unset: ""},
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("restores mode after scoped x group", () => {
        assert.deepEqual(RegexParser.parse("(?x:a b)c d"), {
          type: "concatenation",
          items: [
            {
              type: "optionGroup",
              reset: false,
              set: "x",
              unset: "",
              content: {
                type: "concatenation",
                items: [
                  {type: "literal", codePoint: 97},
                  {type: "literal", codePoint: 98},
                ],
              },
            },
            {type: "literal", codePoint: 99},
            {type: "literal", codePoint: 32},
            {type: "literal", codePoint: 100},
          ],
        });
      });

      it("ignores space in class with inline xx setting", () => {
        assert.deepEqual(RegexParser.parse("(?xx)[a ]"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "xx", unset: ""},
            {
              type: "class",
              negated: false,
              items: [{type: "literal", codePoint: 97}],
            },
          ],
        });
      });

      it("allows spaces in {} bounds regardless of mode", () => {
        assert.deepEqual(RegexParser.parse("a{1, 2}"), {
          type: "quantifier",
          min: 1,
          max: 2,
          mode: "greedy",
          item: {type: "literal", codePoint: 97},
        });
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

    describe("inline options", () => {
      it("parses option setting", () => {
        assert.deepEqual(RegexParser.parse("(?i)a"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "i", unset: ""},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses setting and unsetting multiple options", () => {
        assert.deepEqual(RegexParser.parse("(?im-sU)a"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "im", unset: "sU"},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses option group", () => {
        assert.deepEqual(RegexParser.parse("(?i:ab)"), {
          type: "optionGroup",
          reset: false,
          set: "i",
          unset: "",
          content: {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "literal", codePoint: 98},
            ],
          },
        });
      });

      it("parses option group with unset only", () => {
        assert.deepEqual(RegexParser.parse("(?-i:a)"), {
          type: "optionGroup",
          reset: false,
          set: "",
          unset: "i",
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses reset setting", () => {
        assert.deepEqual(RegexParser.parse("(?^)a"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: true, set: "", unset: ""},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses reset with following options", () => {
        assert.deepEqual(RegexParser.parse("(?^i:a)"), {
          type: "optionGroup",
          reset: true,
          set: "i",
          unset: "",
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses empty unset as no-op", () => {
        assert.deepEqual(RegexParser.parse("(?-)a"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "", unset: ""},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("allows duplicate names after inline J setting", () => {
        assert.deepEqual(RegexParser.parse("(?J)(?<x>a)(?<x>b)"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "J", unset: ""},
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
        });
      });

      it("makes plain groups non-capturing after inline n setting", () => {
        assert.deepEqual(RegexParser.parse("(?n)(a)"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "n", unset: ""},
            {
              type: "nonCapturingGroup",
              content: {type: "literal", codePoint: 97},
            },
          ],
        });
      });

      it("restores parse options after enclosing group closes", () => {
        assertRegexParseError(
          "((?J))(?<x>a)(?<x>b)",
          "two named subpatterns have the same name (PCRE2_DUPNAMES not set)",
          18,
        );
      });

      it("parses ASCII option pair", () => {
        assert.deepEqual(RegexParser.parse("(?aD)b"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "aD", unset: ""},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses bare ASCII option letter", () => {
        assert.deepEqual(RegexParser.parse("(?a)b"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "a", unset: ""},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses unset ASCII option letter", () => {
        assert.deepEqual(RegexParser.parse("(?-a)b"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "", unset: "a"},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses multiple ASCII option pairs", () => {
        assert.deepEqual(RegexParser.parse("(?aDaW)b"), {
          type: "concatenation",
          items: [
            {type: "optionSetting", reset: false, set: "aDaW", unset: ""},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("parses ASCII option group", () => {
        assert.deepEqual(RegexParser.parse("(?aP:b)"), {
          type: "optionGroup",
          reset: false,
          set: "aP",
          unset: "",
          content: {type: "literal", codePoint: 98},
        });
      });

      it("raises on invalid ASCII option pair", () => {
        assertRegexParseError(
          "(?aX)b",
          "unrecognized character after (? or (?-",
          4,
        );
      });

      it("raises on unrecognized option letter", () => {
        assertRegexParseError(
          "(?z)a",
          "unrecognized character after (? or (?-",
          3,
        );
      });

      it("raises on options at end of pattern", () => {
        assertRegexParseError("(?i", "missing closing parenthesis", 3);
      });

      it("raises on hyphen after reset", () => {
        assertRegexParseError("(?^-i)a", "invalid hyphen in option setting", 4);
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
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses negative lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?!a)"), {
          type: "lookaround",
          direction: "ahead",
          negated: true,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses positive lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<=a)"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses negative lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<!a)"), {
          type: "lookaround",
          direction: "behind",
          negated: true,
          atomic: true,
          content: {type: "literal", codePoint: 97},
        });
      });

      it("parses capturing group inside lookahead", () => {
        assert.deepEqual(RegexParser.parse("(?=(a))"), {
          type: "lookaround",
          direction: "ahead",
          negated: false,
          atomic: true,
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
            atomic: true,
            content: {type: "literal", codePoint: 97},
          },
        });
      });

      it("parses bounded variable-length lookbehind", () => {
        assert.deepEqual(RegexParser.parse("(?<=a{0,255})"), {
          type: "lookaround",
          direction: "behind",
          negated: false,
          atomic: true,
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
          atomic: true,
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
          atomic: true,
          content: {
            type: "concatenation",
            items: [
              {
                type: "lookaround",
                direction: "ahead",
                negated: false,
                atomic: true,
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

    describe("quoting", () => {
      it("parses quoted metacharacters as literals", () => {
        assert.deepEqual(RegexParser.parse("\\Qa*\\E"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 42},
          ],
        });
      });

      it("binds quantifier after \\E to the last quoted char", () => {
        assert.deepEqual(RegexParser.parse("\\Qab\\E*"), {
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

      it("quotes to the end of pattern without \\E", () => {
        assert.deepEqual(RegexParser.parse("a\\Qb*"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
            {type: "literal", codePoint: 42},
          ],
        });
      });

      it("ignores \\E without preceding \\Q", () => {
        assert.deepEqual(RegexParser.parse("a\\Eb"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("quotes group metacharacters", () => {
        assert.deepEqual(RegexParser.parse("\\Q(\\E"), {
          type: "literal",
          codePoint: 40,
        });
      });

      it("parses empty quote as nothing", () => {
        assert.deepEqual(RegexParser.parse("\\Q\\Ea"), {
          type: "literal",
          codePoint: 97,
        });
      });

      it("preserves whitespace inside quote in extended mode", () => {
        assert.deepEqual(RegexParser.parse("\\Qa b\\E", {extended: true}), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "literal", codePoint: 32},
            {type: "literal", codePoint: 98},
          ],
        });
      });

      it("raises when quantifier follows empty quote at pattern start", () => {
        assertRegexParseError(
          "\\Q\\E*",
          "quantifier does not follow a repeatable item",
          5,
        );
      });
    });

    describe("start options", () => {
      it("parses option verb", () => {
        assert.deepEqual(RegexParser.parse("(*UTF)a"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "UTF", value: null},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses multiple option verbs", () => {
        assert.deepEqual(RegexParser.parse("(*UTF)(*UCP)a"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "UTF", value: null},
            {type: "startOption", name: "UCP", value: null},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses UTF8 alias", () => {
        assert.deepEqual(RegexParser.parse("(*UTF8)a"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "UTF8", value: null},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses newline convention verb", () => {
        assert.deepEqual(RegexParser.parse("(*CR)a"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "CR", value: null},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("parses limit verb with value", () => {
        assert.deepEqual(RegexParser.parse("(*LIMIT_MATCH=1000)a"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "LIMIT_MATCH", value: 1000},
            {type: "literal", codePoint: 97},
          ],
        });
      });

      it("switches to unicode mode with UTF verb", () => {
        assert.deepEqual(RegexParser.parse("(*UTF)\\x{100}"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "UTF", value: null},
            {type: "literal", codePoint: 256},
          ],
        });
      });

      it("keeps top-level alternation as one item", () => {
        assert.deepEqual(RegexParser.parse("(*UTF)a|b"), {
          type: "concatenation",
          items: [
            {type: "startOption", name: "UTF", value: null},
            {
              type: "alternation",
              branches: [
                {type: "literal", codePoint: 97},
                {type: "literal", codePoint: 98},
              ],
            },
          ],
        });
      });

      it("raises on option verb not at pattern start", () => {
        assertRegexParseError(
          "a(*UTF)",
          "(*VERB) not recognized or malformed",
          6,
        );
      });

      it("raises on limit verb without value", () => {
        assertRegexParseError(
          "(*LIMIT_MATCH)a",
          "(*VERB) not recognized or malformed",
          13,
        );
      });
    });

    describe("subroutine calls", () => {
      it("parses (?R) as whole-pattern recursion", () => {
        assert.deepEqual(RegexParser.parse("(?R)"), {
          type: "subroutine",
          number: 0,
          name: null,
        });
      });

      it("parses quantified recursion", () => {
        assert.deepEqual(RegexParser.parse("a(?R)?"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {
              type: "quantifier",
              min: 0,
              max: 1,
              mode: "greedy",
              item: {type: "subroutine", number: 0, name: null},
            },
          ],
        });
      });

      it("parses (?0) as whole-pattern recursion", () => {
        assert.deepEqual(RegexParser.parse("(?0)"), {
          type: "subroutine",
          number: 0,
          name: null,
        });
      });

      it("parses numeric call", () => {
        assert.deepEqual(RegexParser.parse("(a)(?1)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: 1, name: null},
          ],
        });
      });

      it("resolves negative relative call", () => {
        assert.deepEqual(RegexParser.parse("(a)(?-1)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: 1, name: null},
          ],
        });
      });

      it("resolves positive relative call", () => {
        assert.deepEqual(RegexParser.parse("(?+1)(a)"), {
          type: "concatenation",
          items: [
            {type: "subroutine", number: 1, name: null},
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
          ],
        });
      });

      it("parses (?&name) call", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)(?&x)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: null, name: "x"},
          ],
        });
      });

      it("parses (?P>name) call", () => {
        assert.deepEqual(RegexParser.parse("(?P<x>a)(?P>x)"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: null, name: "x"},
          ],
        });
      });

      it("parses \\g with angle-bracketed number", () => {
        assert.deepEqual(RegexParser.parse("(a)\\g<1>"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: 1, name: null},
          ],
        });
      });

      it("parses \\g with quoted number", () => {
        assert.deepEqual(RegexParser.parse("(a)\\g'1'"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: 1, name: null},
          ],
        });
      });

      it("parses \\g with angle-bracketed name", () => {
        assert.deepEqual(RegexParser.parse("(?<x>a)\\g<x>"), {
          type: "concatenation",
          items: [
            {
              type: "group",
              number: 1,
              name: "x",
              content: {type: "literal", codePoint: 97},
            },
            {type: "subroutine", number: null, name: "x"},
          ],
        });
      });

      it("resolves \\g with relative angle-bracketed number", () => {
        assert.deepEqual(RegexParser.parse("\\g<+1>(a)"), {
          type: "concatenation",
          items: [
            {type: "subroutine", number: 1, name: null},
            {
              type: "group",
              number: 1,
              name: null,
              content: {type: "literal", codePoint: 97},
            },
          ],
        });
      });

      it("raises on (?R without closing parenthesis", () => {
        assertRegexParseError(
          "(?R",
          "(?R (recursive pattern call) must be followed by a closing parenthesis",
          3,
        );
      });

      it("raises on call to non-existent group", () => {
        assertRegexParseError(
          "(a)(?2)",
          "reference to non-existent subpattern",
          6,
        );
      });

      it("raises on relative call before first group", () => {
        assertRegexParseError(
          "(?-1)",
          "reference to non-existent subpattern",
          4,
        );
      });

      it("raises on numeric call without closing parenthesis", () => {
        assertRegexParseError("(?1x)(a)", "missing closing parenthesis", 3);
      });

      it("raises on (?&) without name", () => {
        assertRegexParseError("(?&)", "subpattern name expected", 3);
      });

      it("raises on (?&name) call to non-existent name", () => {
        assertRegexParseError(
          "(?<x>a)(?&y)",
          "reference to non-existent subpattern",
          10,
        );
      });

      it("raises on \\g<> without name", () => {
        assertRegexParseError("(a)\\g<>", "subpattern name expected", 6);
      });

      it("raises on \\g call to non-existent group", () => {
        assertRegexParseError(
          "(a)\\g<2>",
          "reference to non-existent subpattern",
          8,
        );
      });

      it("raises on invalid character in \\g number", () => {
        assertRegexParseError(
          "(a)\\g<1x>",
          "syntax error in subpattern number (missing terminator?)",
          7,
        );
      });
    });

    describe("unicode properties", () => {
      it("parses braced property", () => {
        assert.deepEqual(RegexParser.parse("\\p{L}"), {
          type: "unicodeProperty",
          name: "L",
          negated: false,
        });
      });

      it("parses single-letter property", () => {
        assert.deepEqual(RegexParser.parse("\\pL"), {
          type: "unicodeProperty",
          name: "L",
          negated: false,
        });
      });

      it("parses negated \\P property", () => {
        assert.deepEqual(RegexParser.parse("\\P{L}"), {
          type: "unicodeProperty",
          name: "L",
          negated: true,
        });
      });

      it("parses caret-negated property", () => {
        assert.deepEqual(RegexParser.parse("\\p{^L}"), {
          type: "unicodeProperty",
          name: "L",
          negated: true,
        });
      });

      it("parses double-negated property as positive", () => {
        assert.deepEqual(RegexParser.parse("\\P{^L}"), {
          type: "unicodeProperty",
          name: "L",
          negated: false,
        });
      });

      it("parses script property", () => {
        assert.deepEqual(RegexParser.parse("\\p{Greek}"), {
          type: "unicodeProperty",
          name: "Greek",
          negated: false,
        });
      });

      it("parses name=value property", () => {
        assert.deepEqual(RegexParser.parse("\\p{sc=Greek}"), {
          type: "unicodeProperty",
          name: "sc=Greek",
          negated: false,
        });
      });

      it("parses quantified property", () => {
        assert.deepEqual(RegexParser.parse("\\p{L}+"), {
          type: "quantifier",
          min: 1,
          max: null,
          mode: "greedy",
          item: {type: "unicodeProperty", name: "L", negated: false},
        });
      });

      it("parses properties as class members", () => {
        assert.deepEqual(RegexParser.parse("[\\p{L}\\P{N}]"), {
          type: "class",
          negated: false,
          items: [
            {type: "unicodeProperty", name: "L", negated: false},
            {type: "unicodeProperty", name: "N", negated: true},
          ],
        });
      });

      it("raises on bare \\p", () => {
        assertRegexParseError("\\p", "malformed \\P or \\p sequence", 2);
      });

      it("raises on unterminated property braces", () => {
        assertRegexParseError("\\p{L", "malformed \\P or \\p sequence", 4);
      });

      it("raises on empty property name", () => {
        assertRegexParseError("\\p{}", "unknown property after \\P or \\p", 4);
      });

      it("raises on unknown single-letter property", () => {
        assertRegexParseError("\\pQ", "unknown property after \\P or \\p", 3);
      });

      it("raises on unknown two-letter property", () => {
        assertRegexParseError(
          "\\p{Zz}",
          "unknown property after \\P or \\p",
          6,
        );
      });

      it("raises on property as range endpoint", () => {
        assertRegexParseError(
          "[a-\\p{L}]",
          "invalid range in character class",
          8,
        );
      });
    });

    describe("verbs", () => {
      it("parses (*FAIL)", () => {
        assert.deepEqual(RegexParser.parse("a(*FAIL)"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "verb", verb: "fail", name: null},
          ],
        });
      });

      it("parses (*F) as fail", () => {
        assert.deepEqual(RegexParser.parse("a(*F)"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "verb", verb: "fail", name: null},
          ],
        });
      });

      it("parses all simple verbs", () => {
        assert.deepEqual(
          RegexParser.parse("a(*ACCEPT)(*COMMIT)(*PRUNE)(*SKIP)(*THEN)"),
          {
            type: "concatenation",
            items: [
              {type: "literal", codePoint: 97},
              {type: "verb", verb: "accept", name: null},
              {type: "verb", verb: "commit", name: null},
              {type: "verb", verb: "prune", name: null},
              {type: "verb", verb: "skip", name: null},
              {type: "verb", verb: "then", name: null},
            ],
          },
        );
      });

      it("parses (*MARK:name)", () => {
        assert.deepEqual(RegexParser.parse("a(*MARK:x)"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "verb", verb: "mark", name: "x"},
          ],
        });
      });

      it("parses (*:name) as mark", () => {
        assert.deepEqual(RegexParser.parse("a(*:x)"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "verb", verb: "mark", name: "x"},
          ],
        });
      });

      it("parses named (*SKIP:name)", () => {
        assert.deepEqual(RegexParser.parse("a(*SKIP:x)"), {
          type: "concatenation",
          items: [
            {type: "literal", codePoint: 97},
            {type: "verb", verb: "skip", name: "x"},
          ],
        });
      });

      it("raises on unrecognized verb", () => {
        assertRegexParseError(
          "a(*XYZ)",
          "(*VERB) not recognized or malformed",
          6,
        );
      });

      it("raises on unrecognized lowercase verb", () => {
        assertRegexParseError(
          "a(*fail)",
          "(*alpha_assertion) not recognized",
          8,
        );
      });

      it("raises on empty (*)", () => {
        assertRegexParseError(
          "a(*)",
          "quantifier does not follow a repeatable item",
          3,
        );
      });

      it("raises on (*MARK) without argument", () => {
        assertRegexParseError("a(*MARK)", "(*MARK) must have an argument", 7);
      });

      it("raises on (*MARK:) with empty argument", () => {
        assertRegexParseError("a(*MARK:)", "(*MARK) must have an argument", 8);
      });

      it("raises when quantifier follows verb", () => {
        assertRegexParseError(
          "a(*FAIL)*",
          "quantifier does not follow a repeatable item",
          9,
        );
      });
    });
  });
});

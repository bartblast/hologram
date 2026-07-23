"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexParseError from "../../../assets/js/regex/regex_parse_error.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

const assertParseError = (source, message, position) => {
  let error = null;

  try {
    RegexParser.parse(source);
  } catch (thrownError) {
    error = thrownError;
  }

  assert.instanceOf(error, RegexParseError);
  assert.equal(error.message, message);
  assert.equal(error.position, position);
};

describe("RegexParser", () => {
  describe("parse()", () => {
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

    describe("empty pattern", () => {
      it("parses to empty concatenation", () => {
        assert.deepEqual(RegexParser.parse(""), {
          type: "concatenation",
          items: [],
        });
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
        assertParseError(
          "*",
          "quantifier does not follow a repeatable item",
          1,
        );
      });

      it("raises when quantifier follows quantifier", () => {
        assertParseError(
          "a**",
          "quantifier does not follow a repeatable item",
          3,
        );
      });

      it("raises when {} quantifier has nothing to repeat", () => {
        assertParseError(
          "{2}",
          "quantifier does not follow a repeatable item",
          3,
        );
      });

      it("raises when numbers are out of order", () => {
        assertParseError("a{2,1}", "numbers out of order in {} quantifier", 5);
      });

      it("raises when number is too big", () => {
        assertParseError("a{65536}", "number too big in {} quantifier", 7);
      });
    });

    it("raises on unsupported construct", () => {
      assertParseError("a[", "unsupported pattern construct: [", 1);
    });
  });
});

"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexParseError from "../../../assets/js/regex/regex_parse_error.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

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

    it("raises RegexParseError on unsupported construct", () => {
      assert.throws(
        () => RegexParser.parse("a*"),
        RegexParseError,
        "unsupported pattern construct: *",
      );
    });

    it("includes the position of the unsupported construct", () => {
      let error = null;

      try {
        RegexParser.parse("a*");
      } catch (thrownError) {
        error = thrownError;
      }

      assert.equal(error.position, 1);
    });
  });
});

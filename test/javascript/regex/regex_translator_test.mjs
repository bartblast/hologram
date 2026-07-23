"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexParser from "../../../assets/js/regex/regex_parser.mjs";
import RegexTranslator from "../../../assets/js/regex/regex_translator.mjs";

defineGlobalErlangAndElixirModules();

const translate = (source, opts = {}) =>
  RegexTranslator.translate(RegexParser.parse(source, opts), opts);

describe("RegexTranslator", () => {
  describe("translate()", () => {
    describe("anchors", () => {
      it("translates subject anchors", () => {
        assert.deepEqual(translate("\\Aa\\z"), {source: "^a$", flags: ""});
      });

      it("translates \\Z to end-before-final-newline lookahead", () => {
        assert.deepEqual(translate("a\\Z"), {
          source: "a(?=\\n?$)",
          flags: "",
        });
      });

      it("translates default ^ and $", () => {
        assert.deepEqual(translate("^a$"), {
          source: "^a(?=\\n?$)",
          flags: "",
        });
      });

      it("translates $ with dollar_endonly", () => {
        assert.deepEqual(translate("a$", {dollarEndonly: true}), {
          source: "a$",
          flags: "",
        });
      });

      it("translates multiline ^ and $ via rewrites", () => {
        assert.deepEqual(translate("^a$", {multiline: true}), {
          source: "(?:^|(?<=\\n))a(?=\\n|$)",
          flags: "",
        });
      });

      it("translates word boundaries", () => {
        assert.deepEqual(translate("\\ba\\B"), {
          source: "\\ba\\B",
          flags: "",
        });
      });
    });

    describe("classes", () => {
      it("translates class with range and single chars", () => {
        assert.deepEqual(translate("[a-z0]"), {
          source: "[a-z0]",
          flags: "",
        });
      });

      it("translates negated class", () => {
        assert.deepEqual(translate("[^ab]"), {source: "[^ab]", flags: ""});
      });

      it("escapes ] class member", () => {
        assert.deepEqual(translate("[]a]"), {source: "[\\]a]", flags: ""});
      });

      it("escapes - class member", () => {
        assert.deepEqual(translate("[a-]"), {source: "[a\\-]", flags: ""});
      });

      it("expands shorthand members", () => {
        assert.deepEqual(translate("[\\d\\s]"), {
          source: "[0-9\\x09-\\x0d ]",
          flags: "",
        });
      });

      it("expands negated shorthand member to its complement", () => {
        assert.deepEqual(translate("[\\D]"), {
          source: "[\\x00-/:-ÿ]",
          flags: "",
        });
      });

      it("expands negated shorthand member up to the unicode maximum", () => {
        assert.deepEqual(translate("[\\D]", {unicode: true}), {
          source: "[\\x00-/:-\\u{10ffff}]",
          flags: "u",
        });
      });

      it("expands POSIX class member", () => {
        assert.deepEqual(translate("[[:digit:]]"), {
          source: "[0-9]",
          flags: "",
        });
      });

      it("expands negated POSIX class member to its complement", () => {
        assert.deepEqual(translate("[[:^alpha:]]"), {
          source: "[\\x00-@[-`{-ÿ]",
          flags: "",
        });
      });

      it("expands POSIX class member next to plain members", () => {
        assert.deepEqual(translate("[[:upper:]x]"), {
          source: "[A-Zx]",
          flags: "",
        });
      });
    });

    describe("dot", () => {
      it("translates dot to explicit non-newline class", () => {
        assert.deepEqual(translate("."), {source: "[^\\n]", flags: ""});
      });

      it("translates dot to any-char class in dotall mode", () => {
        assert.deepEqual(translate(".", {dotall: true}), {
          source: "[\\s\\S]",
          flags: "",
        });
      });
    });

    describe("flags", () => {
      it("maps caseless to i", () => {
        assert.deepEqual(translate("a", {caseless: true}), {
          source: "a",
          flags: "i",
        });
      });

      it("maps unicode to u", () => {
        assert.deepEqual(translate("a", {unicode: true}), {
          source: "a",
          flags: "u",
        });
      });

      it("combines flags", () => {
        assert.deepEqual(translate("a", {caseless: true, unicode: true}), {
          source: "a",
          flags: "iu",
        });
      });
    });

    describe("groups and alternation", () => {
      it("translates alternation", () => {
        assert.deepEqual(translate("a|b"), {source: "a|b", flags: ""});
      });

      it("wraps alternation after start options in non-capturing group", () => {
        assert.deepEqual(translate("(*NO_JIT)a|b"), {
          source: "(?:a|b)",
          flags: "",
        });
      });

      it("translates capturing group", () => {
        assert.deepEqual(translate("(a|b)c"), {source: "(a|b)c", flags: ""});
      });

      it("translates named group", () => {
        assert.deepEqual(translate("(?<x>a)"), {
          source: "(?<x>a)",
          flags: "",
        });
      });

      it("translates non-capturing group", () => {
        assert.deepEqual(translate("(?:ab)"), {source: "(?:ab)", flags: ""});
      });

      it("translates numeric backreference", () => {
        assert.deepEqual(translate("(a)\\1"), {source: "(a)\\1", flags: ""});
      });

      it("translates named backreference", () => {
        assert.deepEqual(translate("(?<x>a)\\k<x>"), {
          source: "(?<x>a)\\k<x>",
          flags: "",
        });
      });

      it("translates lookarounds", () => {
        assert.deepEqual(translate("(?=a)(?!b)(?<=c)(?<!d)"), {
          source: "(?=a)(?!b)(?<=c)(?<!d)",
          flags: "",
        });
      });
    });

    describe("literals", () => {
      it("translates plain chars as-is", () => {
        assert.deepEqual(translate("abc"), {source: "abc", flags: ""});
      });

      it("escapes metacharacter literals", () => {
        assert.deepEqual(translate("a\\.b\\*"), {
          source: "a\\.b\\*",
          flags: "",
        });
      });

      it("translates control char to hex escape", () => {
        assert.deepEqual(translate("\\x01"), {source: "\\x01", flags: ""});
      });

      it("translates non-ASCII BMP char as-is", () => {
        assert.deepEqual(translate("é"), {source: "é", flags: ""});
      });

      it("translates astral char to braced escape in unicode mode", () => {
        assert.deepEqual(translate("😀", {unicode: true}), {
          source: "\\u{1f600}",
          flags: "u",
        });
      });
    });

    describe("escape rewrites", () => {
      it("translates \\d and \\w directly", () => {
        assert.deepEqual(translate("\\d\\D\\w\\W"), {
          source: "\\d\\D\\w\\W",
          flags: "",
        });
      });

      it("rewrites \\s to the PCRE2 whitespace set", () => {
        assert.deepEqual(translate("\\s\\S"), {
          source: "[\\x09-\\x0d ][^\\x09-\\x0d ]",
          flags: "",
        });
      });

      it("rewrites \\h to the horizontal whitespace set", () => {
        assert.deepEqual(translate("\\h"), {
          source: "[\\x09 \u00a0\u1680\u180e\u2000-\u200a\u202f\u205f\u3000]",
          flags: "",
        });
      });

      it("rewrites \\v to the vertical whitespace set", () => {
        assert.deepEqual(translate("\\v"), {
          source: "[\\x0a-\\x0d\u0085\u2028-\u2029]",
          flags: "",
        });
      });

      it("rewrites \\R to the newline sequence alternation", () => {
        assert.deepEqual(translate("\\R"), {
          source: "(?:\\r\\n|[\\x0a-\\x0d\u0085\u2028-\u2029])",
          flags: "",
        });
      });

      it("rewrites \\N to the non-newline class", () => {
        assert.deepEqual(translate("\\N", {dotall: true}), {
          source: "[^\\n]",
          flags: "",
        });
      });
    });

    describe("quantifiers", () => {
      it("translates simple quantifiers", () => {
        assert.deepEqual(translate("a*b+c?"), {source: "a*b+c?", flags: ""});
      });

      it("translates bounded quantifiers", () => {
        assert.deepEqual(translate("a{2}b{2,}c{2,5}"), {
          source: "a{2}b{2,}c{2,5}",
          flags: "",
        });
      });

      it("translates lazy quantifier", () => {
        assert.deepEqual(translate("a*?"), {source: "a*?", flags: ""});
      });
    });

    it("produces a working RegExp", () => {
      const {source, flags} = translate("(a|b)+[c-e]{2}");
      const regex = new RegExp(source, flags);

      assert.isTrue(regex.test("abcd"));
      assert.isFalse(regex.test("abcf"));
    });
  });
});

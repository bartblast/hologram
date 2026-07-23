"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexParser from "../../../assets/js/regex/regex_parser.mjs";
import RegexTranslator from "../../../assets/js/regex/regex_translator.mjs";

defineGlobalErlangAndElixirModules();

const translate = (source, opts = {}) => {
  const {source: jsSource, flags} = translateFull(source, opts);

  return {source: jsSource, flags: flags};
};

const translateFull = (source, opts = {}) =>
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

    describe("atomic groups and possessive quantifiers", () => {
      it("emulates atomic group with capturing lookahead", () => {
        assert.deepEqual(translate("(?>a+)b"), {
          source: "(?=(a+))\\1b",
          flags: "",
        });
      });

      it("emulates possessive star", () => {
        assert.deepEqual(translate("a*+b"), {
          source: "(?=(a*))\\1b",
          flags: "",
        });
      });

      it("emulates possessive bounded quantifier", () => {
        assert.deepEqual(translate("a{2,5}+"), {
          source: "(?=(a{2,5}))\\1",
          flags: "",
        });
      });

      it("renumbers groups after synthetic group", () => {
        assert.deepEqual(translateFull("(a)(?>b)(c)\\2"), {
          source: "(a)(?=(b))\\2(c)\\3",
          flags: "",
          groupMapping: new Map([
            [1, 1],
            [2, 3],
          ]),
        });
      });

      it("numbers groups nested inside atomic group after the synthetic one", () => {
        assert.deepEqual(translateFull("(?>(a))"), {
          source: "(?=((a)))\\1",
          flags: "",
          groupMapping: new Map([[1, 2]]),
        });
      });

      it("keeps named groups and references intact", () => {
        assert.deepEqual(translate("(?<x>a)(?>b)\\k<x>"), {
          source: "(?<x>a)(?=(b))\\2\\k<x>",
          flags: "",
        });
      });

      it("returns identity mapping without synthetic groups", () => {
        assert.deepEqual(
          translateFull("(a)(b)").groupMapping,
          new Map([
            [1, 1],
            [2, 2],
          ]),
        );
      });

      it("produces a RegExp with atomic semantics", () => {
        const {source, flags} = translate("(?>a+)a");
        const regex = new RegExp(source, flags);

        assert.isFalse(regex.test("aaa"));
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

    describe("inline options", () => {
      it("translates caseless option group to modifier group", () => {
        assert.deepEqual(translate("(?i:a)b"), {
          source: "(?i:a)b",
          flags: "",
        });
      });

      it("translates caseless-unsetting option group to modifier group", () => {
        assert.deepEqual(translate("(?-i:a)b", {caseless: true}), {
          source: "(?-i:a)b",
          flags: "i",
        });
      });

      it("translates multiline option group via anchor rewrites", () => {
        assert.deepEqual(translate("(?m:^a)$"), {
          source: "(?:(?:^|(?<=\\n))a)(?=\\n?$)",
          flags: "",
        });
      });

      it("translates dotall option group via dot rewrites", () => {
        assert.deepEqual(translate("(?s:.)."), {
          source: "(?:[\\s\\S])[^\\n]",
          flags: "",
        });
      });

      it("translates ungreedy option group via quantifier flips", () => {
        assert.deepEqual(translate("(?U:a*)a*"), {
          source: "(?:a*?)a*",
          flags: "",
        });
      });

      it("scopes inline setting to the rest of the pattern", () => {
        assert.deepEqual(translate("a(?i)bc"), {
          source: "a(?i:bc)",
          flags: "",
        });
      });

      it("scopes non-caseless inline setting without a wrapper", () => {
        assert.deepEqual(translate("a(?s).b."), {
          source: "a[\\s\\S]b[\\s\\S]",
          flags: "",
        });
      });

      it("resets options with inline reset setting", () => {
        assert.deepEqual(translate("(?i)a(?^)b"), {
          source: "(?i:a(?-i:b))",
          flags: "",
        });
      });

      it("scopes inline setting to its enclosing group", () => {
        assert.deepEqual(translate("(?:(?i)a)b"), {
          source: "(?:(?i:a))b",
          flags: "",
        });
      });
    });

    describe("newline conventions", () => {
      it("excludes the convention newline from dot", () => {
        assert.deepEqual(translate(".", {newline: "cr"}), {
          source: "[^\\r]",
          flags: "",
        });
      });

      it("excludes nothing from dot under crlf", () => {
        assert.deepEqual(translate(".", {newline: "crlf"}), {
          source: "[\\s\\S]",
          flags: "",
        });
      });

      it("excludes both chars from dot under anycrlf", () => {
        assert.deepEqual(translate(".", {newline: "anycrlf"}), {
          source: "[^\\r\\n]",
          flags: "",
        });
      });

      it("excludes all newline chars from dot under any", () => {
        assert.deepEqual(translate(".", {newline: "any"}), {
          source: "[^\\x0a-\\x0d\\u0085\\u2028-\\u2029]",
          flags: "",
        });
      });

      it("applies the convention to \\N regardless of dotall", () => {
        assert.deepEqual(translate("\\N", {dotall: true, newline: "crlf"}), {
          source: "[\\s\\S]",
          flags: "",
        });
      });

      it("applies the convention to multiline anchors", () => {
        assert.deepEqual(
          translate("^a$", {multiline: true, newline: "anycrlf"}),
          {
            source: "(?:^|(?<=\\n)|(?<=\\r)(?!\\n))a(?=\\r|\\n|$)",
            flags: "",
          },
        );
      });

      it("applies the convention to default $", () => {
        assert.deepEqual(translate("a$", {newline: "crlf"}), {
          source: "a(?=(?:\\r\\n)?$)",
          flags: "",
        });
      });

      it("applies the convention to \\Z", () => {
        assert.deepEqual(translate("a\\Z", {newline: "cr"}), {
          source: "a(?=\\r?$)",
          flags: "",
        });
      });

      it("restricts \\R with bsr_anycrlf", () => {
        assert.deepEqual(translate("\\R", {bsrAnycrlf: true}), {
          source: "(?:\\r\\n|[\\r\\n])",
          flags: "",
        });
      });

      it("applies newline convention start verb", () => {
        assert.deepEqual(translate("(*CR)."), {
          source: "[^\\r]",
          flags: "",
        });
      });

      it("applies bsr start verb", () => {
        assert.deepEqual(translate("(*BSR_ANYCRLF)\\R"), {
          source: "(?:\\r\\n|[\\r\\n])",
          flags: "",
        });
      });

      it("applies UTF start verb to flags", () => {
        assert.deepEqual(translate("(*UTF)a"), {source: "a", flags: "u"});
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

      it("swaps greediness with ungreedy option", () => {
        assert.deepEqual(translate("a*b*?", {ungreedy: true}), {
          source: "a*?b*",
          flags: "",
        });
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

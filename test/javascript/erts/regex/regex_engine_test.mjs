"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Bitstring from "../../../../assets/js/bitstring.mjs";
import RegexEngine from "../../../../assets/js/erts/regex/regex_engine.mjs";
import Type from "../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const match = (source, subject, opts = {}, runOpts = {}) =>
  RegexEngine.match(RegexEngine.compile(source, opts), subject, runOpts);

describe("RegexEngine", () => {
  describe("byteOffsetToUtf16Index()", () => {
    // a: 1 byte / 1 UTF-16 unit, é: 2 bytes / 1 unit, €: 3 bytes / 1 unit, 😀: 4 bytes / 2 units
    const text = "aé€😀";

    it("returns 0 for offset 0", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 0), 0);
    });

    it("converts offset after 1-byte code point", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 1), 1);
    });

    it("converts offset after 2-byte code point", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 3), 2);
    });

    it("converts offset after 3-byte code point", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 6), 3);
    });

    it("converts offset after 4-byte code point", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 10), 5);
    });

    it("clamps offset past the end of text", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index(text, 11), 5);
    });

    it("returns 0 for empty text", () => {
      assert.equal(RegexEngine.byteOffsetToUtf16Index("", 3), 0);
    });
  });

  describe("charDataToText()", () => {
    it("converts a binary, decoding UTF-8", () => {
      assert.equal(RegexEngine.charDataToText(Type.bitstring("aé")), "aé");
    });

    it("converts a nested list with an improper binary tail", () => {
      const charData = Type.improperList([
        Type.integer(97),
        Type.list([Type.integer(233)]),
        Type.bitstring("b"),
        Type.bitstring("c"),
      ]);

      assert.equal(RegexEngine.charDataToText(charData), "aébc");
    });

    it("raises ArgumentError on an invalid code point", () => {
      assertBoxedError(
        () => RegexEngine.charDataToText(Type.list([Type.integer(0x110000)])),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on a non-UTF-8 binary", () => {
      assertBoxedError(
        () => RegexEngine.charDataToText(Bitstring.fromBytes([255])),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError on a term that is not char data", () => {
      assertBoxedError(
        () => RegexEngine.charDataToText(Type.atom("abc")),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("compareByUtf8Bytes()", () => {
    it("returns a negative number when the first string sorts lower", () => {
      assert.isBelow(RegexEngine.compareByUtf8Bytes("aa", "ab"), 0);
    });

    it("returns zero for equal strings", () => {
      assert.equal(RegexEngine.compareByUtf8Bytes("abc", "abc"), 0);
    });

    it("sorts a prefix before its extension", () => {
      assert.isAbove(RegexEngine.compareByUtf8Bytes("abc", "ab"), 0);
    });

    it("sorts astral code points after BMP ones, unlike default JS order", () => {
      assert.isAbove(RegexEngine.compareByUtf8Bytes("\u{10000}", "\uffff"), 0);
      assert.isTrue("\u{10000}" < "\uffff");
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

    it("defaults the newline type to lf", () => {
      assert.equal(RegexEngine.compile("ab").newlineType, "lf");
    });

    it("takes the newline type from the newline option", () => {
      assert.equal(
        RegexEngine.compile("ab", {newline: "crlf"}).newlineType,
        "crlf",
      );
    });

    it("newline verb beats the newline option", () => {
      assert.equal(
        RegexEngine.compile("(*LF)ab", {newline: "crlf"}).newlineType,
        "lf",
      );
    });

    it("last newline verb wins", () => {
      assert.equal(RegexEngine.compile("(*CRLF)(*LF)ab").newlineType, "lf");
    });

    it("returns the parse error as data on invalid pattern", () => {
      assert.deepEqual(RegexEngine.compile("a{2,1}"), {
        error: {message: "numbers out of order in {} quantifier", position: 5},
      });
    });
  });

  describe("compileBytes()", () => {
    // (*UTF)é: ASCII verb bytes followed by the 2-byte UTF-8 encoding of é
    const utfVerbBytes = [0x28, 0x2a, 0x55, 0x54, 0x46, 0x29];

    it("expands bytes as latin-1 without the unicode option", () => {
      const compiled = RegexEngine.compileBytes(
        new Uint8Array([0x61, 0xe9]),
        {},
      );

      assert.equal(compiled.source, "aé");
      assert.isUndefined(compiled.opts.unicode);
    });

    it("decodes bytes as UTF-8 with the unicode option", () => {
      const compiled = RegexEngine.compileBytes(new Uint8Array([0xc3, 0xa9]), {
        unicode: true,
      });

      assert.equal(compiled.source, "é");
      assert.isTrue(compiled.opts.unicode);
    });

    it("switches to UTF-8 with a UTF start option verb", () => {
      const compiled = RegexEngine.compileBytes(
        new Uint8Array([...utfVerbBytes, 0xc3, 0xa9]),
        {},
      );

      assert.equal(compiled.source, "(*UTF)é");
      assert.isTrue(compiled.opts.unicode);
    });

    it("keeps latin-1 with a UTF start option verb when UTF is disabled", () => {
      const result = RegexEngine.compileBytes(
        new Uint8Array([...utfVerbBytes, 0x61]),
        {never_utf: true},
      );

      assert.deepEqual(result, {
        error: {
          message: "using UTF is disabled by the application",
          position: 6,
        },
      });
    });

    it("returns a UTF-8 error with byte position in unicode mode", () => {
      const result = RegexEngine.compileBytes(new Uint8Array([0x61, 0xff]), {
        unicode: true,
      });

      assert.deepEqual(result, {
        error: {
          message: "UTF-8 error: illegal byte (0xfe or 0xff)",
          position: 1,
        },
      });
    });

    it("returns a UTF-8 error from the UTF start option verb switch", () => {
      const result = RegexEngine.compileBytes(
        new Uint8Array([...utfVerbBytes, 0xff]),
        {},
      );

      assert.deepEqual(result, {
        error: {
          message: "UTF-8 error: illegal byte (0xfe or 0xff)",
          position: 6,
        },
      });
    });

    it("converts parse error positions to byte offsets in unicode mode", () => {
      const result = RegexEngine.compileBytes(
        new Uint8Array([0xc3, 0xa9, 0x28]),
        {unicode: true},
      );

      assert.deepEqual(result, {
        error: {message: "missing closing parenthesis", position: 3},
      });
    });

    it("keeps parse error positions as byte offsets in latin-1 mode", () => {
      const result = RegexEngine.compileBytes(new Uint8Array([0xe9, 0x28]), {});

      assert.deepEqual(result, {
        error: {message: "missing closing parenthesis", position: 2},
      });
    });
  });

  describe("decodeUtf8()", () => {
    const decode = (bytes) => RegexEngine.decodeUtf8(new Uint8Array(bytes));

    const assertError = (bytes, message, position) => {
      assert.deepEqual(decode(bytes), {
        error: {message: message, position: position},
      });
    };

    it("decodes empty input", () => {
      assert.deepEqual(decode([]), {text: ""});
    });

    it("decodes ASCII bytes", () => {
      assert.deepEqual(decode([0x61, 0x62, 0x63]), {text: "abc"});
    });

    it("decodes multi-byte characters of each length", () => {
      // a: 1 byte, é: 2 bytes, €: 3 bytes, 😀: 4 bytes
      assert.deepEqual(
        decode([0x61, 0xc3, 0xa9, 0xe2, 0x82, 0xac, 0xf0, 0x9f, 0x98, 0x80]),
        {text: "aé€😀"},
      );
    });

    it("rejects isolated continuation byte", () => {
      assertError([0x80], "UTF-8 error: isolated byte with 0x80 bit set", 0);
    });

    it("rejects 0xfe and 0xff bytes", () => {
      assertError(
        [0x61, 0x62, 0xff],
        "UTF-8 error: illegal byte (0xfe or 0xff)",
        2,
      );
    });

    it("rejects truncated character with 1 byte missing at end", () => {
      assertError([0xe2, 0x82], "UTF-8 error: 1 byte missing at end", 0);
    });

    it("rejects truncated character with 2 bytes missing at end", () => {
      assertError([0x78, 0x79, 0xe2], "UTF-8 error: 2 bytes missing at end", 2);
    });

    it("rejects truncated character with 3 bytes missing at end", () => {
      assertError([0xf0], "UTF-8 error: 3 bytes missing at end", 0);
    });

    it("rejects truncated 5-byte character", () => {
      assertError(
        [0xf8, 0x88, 0x80, 0x80],
        "UTF-8 error: 1 byte missing at end",
        0,
      );
    });

    it("rejects bad byte 2 top bits", () => {
      assertError([0xc3, 0x28], "UTF-8 error: byte 2 top bits not 0x80", 0);
    });

    it("rejects bad byte 3 top bits", () => {
      assertError(
        [0xe2, 0x82, 0x28],
        "UTF-8 error: byte 3 top bits not 0x80",
        0,
      );
    });

    it("rejects bad byte 4 top bits", () => {
      assertError(
        [0xf0, 0x90, 0x80, 0x28],
        "UTF-8 error: byte 4 top bits not 0x80",
        0,
      );
    });

    it("rejects bad byte 5 top bits", () => {
      assertError(
        [0xf8, 0x88, 0x80, 0x80, 0x28],
        "UTF-8 error: byte 5 top bits not 0x80",
        0,
      );
    });

    it("rejects bad byte 6 top bits", () => {
      assertError(
        [0xfc, 0x84, 0x80, 0x80, 0x80, 0x28],
        "UTF-8 error: byte 6 top bits not 0x80",
        0,
      );
    });

    it("rejects overlong 2-byte sequence", () => {
      assertError([0xc0, 0x80], "UTF-8 error: overlong 2-byte sequence", 0);
    });

    it("rejects overlong 3-byte sequence", () => {
      assertError(
        [0xe0, 0x80, 0x80],
        "UTF-8 error: overlong 3-byte sequence",
        0,
      );
    });

    it("rejects overlong 4-byte sequence", () => {
      assertError(
        [0xf0, 0x80, 0x80, 0x80],
        "UTF-8 error: overlong 4-byte sequence",
        0,
      );
    });

    it("rejects overlong 5-byte sequence", () => {
      assertError(
        [0xf8, 0x80, 0x80, 0x80, 0x80],
        "UTF-8 error: overlong 5-byte sequence",
        0,
      );
    });

    it("rejects overlong 6-byte sequence", () => {
      assertError(
        [0xfc, 0x80, 0x80, 0x80, 0x80, 0x80],
        "UTF-8 error: overlong 6-byte sequence",
        0,
      );
    });

    it("rejects surrogate code points", () => {
      assertError(
        [0xed, 0xa0, 0x80],
        "UTF-8 error: code points 0xd800-0xdfff are not defined",
        0,
      );
    });

    it("rejects code points greater than 0x10ffff", () => {
      assertError(
        [0xf4, 0x90, 0x80, 0x80],
        "UTF-8 error: code points greater than 0x10ffff are not defined",
        0,
      );
    });

    it("rejects code points greater than 0x10ffff from 0xf5 lead byte", () => {
      assertError(
        [0xf5, 0x80, 0x80, 0x80],
        "UTF-8 error: code points greater than 0x10ffff are not defined",
        0,
      );
    });

    it("rejects 5-byte character with valid continuation bytes", () => {
      assertError(
        [0xf8, 0x88, 0x80, 0x80, 0x80],
        "UTF-8 error: 5-byte character is not allowed (RFC 3629)",
        0,
      );
    });

    it("rejects 6-byte character with valid continuation bytes", () => {
      assertError(
        [0xfc, 0x84, 0x80, 0x80, 0x80, 0x80],
        "UTF-8 error: 6-byte character is not allowed (RFC 3629)",
        0,
      );
    });
  });

  describe("hasUtfStartOption()", () => {
    it("returns true for UTF verb at pattern start", () => {
      assert.isTrue(RegexEngine.hasUtfStartOption("(*UTF)a"));
    });

    it("returns true for UTF8 alias", () => {
      assert.isTrue(RegexEngine.hasUtfStartOption("(*UTF8)a"));
    });

    it("returns true for UTF verb after other option verbs", () => {
      assert.isTrue(RegexEngine.hasUtfStartOption("(*UCP)(*CRLF)(*UTF)a"));
    });

    it("returns true for UTF verb after limit verb with value", () => {
      assert.isTrue(RegexEngine.hasUtfStartOption("(*LIMIT_MATCH=100)(*UTF)a"));
    });

    it("returns false without UTF verb", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("abc"));
    });

    it("returns false for other option verbs only", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*CRLF)a"));
    });

    it("returns false for UTF verb after backtracking verb", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*COMMIT)(*UTF)a"));
    });

    it("returns false for UTF verb after unknown verb", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*FOO)(*UTF)a"));
    });

    it("returns false for UTF verb not at pattern start", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("a(*UTF)"));
    });

    it("returns false for unterminated verb", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*UTF"));
    });

    it("returns false for UTF verb after limit verb without value", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*LIMIT_MATCH)(*UTF)a"));
    });

    it("returns false for UTF verb after option verb with unexpected value", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption("(*CRLF=5)(*UTF)a"));
    });

    it("returns false for empty source", () => {
      assert.isFalse(RegexEngine.hasUtfStartOption(""));
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

    it("anchored matches at the start position on the native engine", () => {
      assert.deepEqual(match("a", "ab", {}, {anchored: true}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("anchored matches at the start position on the interpreter", () => {
      assert.deepEqual(match("a\\Kb", "ab", {}, {anchored: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("anchored returns null off the start position on the native engine", () => {
      assert.isNull(match("b", "ab", {}, {anchored: true}));
    });

    it("anchored returns null off the start position on the interpreter", () => {
      assert.isNull(match("b\\K", "ab", {}, {anchored: true}));
    });

    it("anchored honors the start position on the native engine", () => {
      assert.deepEqual(
        match("b", "ab", {}, {anchored: true, startPosition: 1}),
        {
          start: 1,
          end: 2,
          captures: [null],
        },
      );
    });

    it("anchored honors the start position on the interpreter", () => {
      assert.deepEqual(
        match("b\\K", "ab", {}, {anchored: true, startPosition: 1}),
        {start: 2, end: 2, captures: [null]},
      );
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

    it("notbol makes ^ fail at the subject start", () => {
      assert.isNull(match("^a", "ab", {}, {notbol: true}));
    });

    it("notbol keeps ^ matching after an internal newline", () => {
      assert.deepEqual(match("^b", "a\nb", {multiline: true}, {notbol: true}), {
        start: 2,
        end: 3,
        captures: [null],
      });
    });

    it("notbol doesn't affect \\A", () => {
      assert.deepEqual(match("\\Aa", "ab", {}, {notbol: true}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("noteol makes $ fail at the subject end", () => {
      assert.isNull(match("b$", "ab", {}, {noteol: true}));
    });

    it("noteol makes $ fail before a final newline", () => {
      assert.isNull(match("b$", "ab\n", {}, {noteol: true}));
    });

    it("noteol keeps $ matching before an internal newline", () => {
      assert.deepEqual(match("a$", "a\nb", {multiline: true}, {noteol: true}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("noteol makes multiline $ fail at the subject end", () => {
      assert.isNull(match("b$", "a\nb", {multiline: true}, {noteol: true}));
    });

    it("noteol makes dollar_endonly $ fail at the subject end", () => {
      assert.isNull(match("b$", "ab", {dollar_endonly: true}, {noteol: true}));
    });

    it("noteol doesn't affect \\Z", () => {
      assert.deepEqual(match("b\\Z", "ab", {}, {noteol: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("notempty backtracks to a non-empty match", () => {
      assert.deepEqual(match("|a", "a", {}, {notempty: true}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("notempty rejects empty matches at every position", () => {
      assert.isNull(match("a*", "b", {}, {notempty: true}));
    });

    it("notempty scans past rejected empty matches", () => {
      assert.deepEqual(match("a*", "ba", {}, {notempty: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("notempty rejects an empty match reported after \\K", () => {
      assert.isNull(match("a\\K", "a", {}, {notempty: true}));
    });

    it("notempty rejects an empty accepted match", () => {
      assert.isNull(match("(*ACCEPT)", "a", {}, {notempty: true}));
    });

    it("notemptyAtStart rejects an empty match at the start position", () => {
      assert.deepEqual(match("a*", "ba", {}, {notemptyAtStart: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("notemptyAtStart allows an empty match past the start position", () => {
      assert.deepEqual(
        match("b*", "ba", {}, {notemptyAtStart: true, startPosition: 1}),
        {start: 2, end: 2, captures: [null]},
      );
    });

    it("firstline rejects a match past the first newline", () => {
      assert.isNull(match("b", "a\nb", {}, {firstline: true}));
    });

    it("firstline allows a match before the first newline", () => {
      assert.deepEqual(match("b", "ab\ncd", {}, {firstline: true}), {
        start: 1,
        end: 2,
        captures: [null],
      });
    });

    it("firstline allows a match starting at the first newline", () => {
      assert.deepEqual(match("\\nb", "a\nb", {}, {firstline: true}), {
        start: 1,
        end: 3,
        captures: [null],
      });
    });

    it("firstline allows a match crossing the first newline", () => {
      assert.deepEqual(match("b\\nc", "ab\ncd", {}, {firstline: true}), {
        start: 1,
        end: 4,
        captures: [null],
      });
    });

    it("firstline bounds the attempt start, not the reported start", () => {
      assert.deepEqual(match("a\\n\\Kb", "a\nb", {}, {firstline: true}), {
        start: 2,
        end: 3,
        captures: [null],
      });
    });

    it("firstline rejects an attempt past the first newline on the interpreter", () => {
      assert.isNull(match("b\\K", "a\nb", {}, {firstline: true}));
    });

    it("firstline uses the newline convention", () => {
      assert.isNull(
        match("b", "a\rb", {newline: "anycrlf"}, {firstline: true}),
      );
    });

    it("firstline counts newlines from the start position", () => {
      assert.deepEqual(
        match("b", "a\nb", {}, {firstline: true, startPosition: 2}),
        {start: 2, end: 3, captures: [null]},
      );
    });

    it("an exceeded match limit reports no match", () => {
      assert.isNull(match("a", "a", {}, {matchLimit: 0}));
    });

    it("matches within the match limit", () => {
      assert.deepEqual(match("a", "a", {}, {matchLimit: 100}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("the match limit stops runaway backtracking", () => {
      assert.isNull(match("(a+)+b", "aaaaaaaaaax", {}, {matchLimit: 1}));
    });

    it("an exceeded recursion limit reports no match", () => {
      assert.isNull(match("a", "a", {}, {matchLimitRecursion: 0}));
    });

    it("matches within the recursion limit", () => {
      assert.deepEqual(match("a", "a", {}, {matchLimitRecursion: 100}), {
        start: 0,
        end: 1,
        captures: [null],
      });
    });

    it("a lower match limit verb beats the run limit", () => {
      assert.isNull(
        match("(*LIMIT_MATCH=5)(a+)+b", "aaaaaaaaaax", {}, {matchLimit: 1000}),
      );
    });

    it("a lower run limit beats the match limit verb", () => {
      assert.isNull(
        match("(*LIMIT_MATCH=1000)(a+)+b", "aaaaaaaaaax", {}, {matchLimit: 1}),
      );
    });
  });

  describe("matchGlobal()", () => {
    const matchGlobal = (source, subject, opts = {}, runOpts = {}) =>
      RegexEngine.matchGlobal(
        RegexEngine.compile(source, opts),
        subject,
        runOpts,
      );

    it("collects successive matches", () => {
      assert.deepEqual(matchGlobal("a", "abab"), [
        {start: 0, end: 1, captures: [null]},
        {start: 2, end: 3, captures: [null]},
      ]);
    });

    it("collects captures per match", () => {
      assert.deepEqual(matchGlobal("a(b)", "abab"), [
        {start: 0, end: 2, captures: [null, {start: 1, end: 2}]},
        {start: 2, end: 4, captures: [null, {start: 3, end: 4}]},
      ]);
    });

    it("returns an empty array without a match", () => {
      assert.deepEqual(matchGlobal("x", "ab"), []);
    });

    it("continues at the previous match end", () => {
      assert.deepEqual(matchGlobal("a\\Kb", "abab"), [
        {start: 1, end: 2, captures: [null]},
        {start: 3, end: 4, captures: [null]},
      ]);
    });

    it("advances past an empty match", () => {
      assert.deepEqual(matchGlobal("a*", "ab"), [
        {start: 0, end: 1, captures: [null]},
        {start: 1, end: 1, captures: [null]},
        {start: 2, end: 2, captures: [null]},
      ]);
    });

    it("reports a successful anchored retry after an empty match", () => {
      assert.deepEqual(matchGlobal("|a", "a"), [
        {start: 0, end: 0, captures: [null]},
        {start: 0, end: 1, captures: [null]},
        {start: 1, end: 1, captures: [null]},
      ]);
    });

    it("matches once on an empty subject", () => {
      assert.deepEqual(matchGlobal("", ""), [
        {start: 0, end: 0, captures: [null]},
      ]);
    });

    it("advances over a CRLF pair as one newline", () => {
      assert.deepEqual(matchGlobal("", "\r\n", {newline: "crlf"}), [
        {start: 0, end: 0, captures: [null]},
        {start: 2, end: 2, captures: [null]},
      ]);
    });

    it("advances into a CRLF pair with the lf convention", () => {
      assert.deepEqual(matchGlobal("", "\r\n"), [
        {start: 0, end: 0, captures: [null]},
        {start: 1, end: 1, captures: [null]},
        {start: 2, end: 2, captures: [null]},
      ]);
    });

    it("advances over an astral character in unicode mode", () => {
      assert.deepEqual(matchGlobal("x*", "😀", {unicode: true}), [
        {start: 0, end: 0, captures: [null]},
        {start: 2, end: 2, captures: [null]},
      ]);
    });

    it("anchored continues while matches are adjacent", () => {
      assert.deepEqual(matchGlobal("a", "aab", {}, {anchored: true}), [
        {start: 0, end: 1, captures: [null]},
        {start: 1, end: 2, captures: [null]},
      ]);
    });

    it("anchored stops at the first failed position", () => {
      assert.deepEqual(matchGlobal("a", "aba", {}, {anchored: true}), [
        {start: 0, end: 1, captures: [null]},
      ]);
    });

    it("anchored still advances past a rejected empty retry", () => {
      assert.deepEqual(matchGlobal("a*", "ab", {}, {anchored: true}), [
        {start: 0, end: 1, captures: [null]},
        {start: 1, end: 1, captures: [null]},
        {start: 2, end: 2, captures: [null]},
      ]);
    });

    it("starts at the start position", () => {
      assert.deepEqual(matchGlobal("a", "abab", {}, {startPosition: 1}), [
        {start: 2, end: 3, captures: [null]},
      ]);
    });

    it("returns an empty array with the start position past the subject", () => {
      assert.deepEqual(matchGlobal("a", "ab", {}, {startPosition: 3}), []);
    });

    it("applies scan flags to every attempt", () => {
      assert.deepEqual(matchGlobal("a*", "ab", {}, {notempty: true}), [
        {start: 0, end: 1, captures: [null]},
      ]);
    });

    it("recomputes the firstline bound per attempt", () => {
      assert.deepEqual(matchGlobal("[a-d]", "ab\ncd", {}, {firstline: true}), [
        {start: 0, end: 1, captures: [null]},
        {start: 1, end: 2, captures: [null]},
      ]);
    });
  });

  describe("parseCompileOption()", () => {
    const buildAcc = () => ({
      anchored: false,
      engineOpts: {},
      firstline: false,
      unicodeOption: false,
    });

    it("classifies an engine option atom as compile and enables the engine opt", () => {
      const acc = buildAcc();
      const kind = RegexEngine.parseCompileOption(Type.atom("caseless"), acc);

      assert.equal(kind, "compile");
      assert.deepEqual(acc.engineOpts, {caseless: true});
    });

    it("classifies anchored and sets the anchored flag", () => {
      const acc = buildAcc();
      const kind = RegexEngine.parseCompileOption(Type.atom("anchored"), acc);

      assert.equal(kind, "anchored");
      assert.isTrue(acc.anchored);
      assert.deepEqual(acc.engineOpts, {});
    });

    it("classifies firstline as compile and sets the firstline flag", () => {
      const acc = buildAcc();
      const kind = RegexEngine.parseCompileOption(Type.atom("firstline"), acc);

      assert.equal(kind, "compile");
      assert.isTrue(acc.firstline);
      assert.deepEqual(acc.engineOpts, {});
    });

    it("classifies no_start_optimize as compile without engine opts", () => {
      const acc = buildAcc();

      const kind = RegexEngine.parseCompileOption(
        Type.atom("no_start_optimize"),
        acc,
      );

      assert.equal(kind, "compile");
      assert.deepEqual(acc.engineOpts, {});
    });

    it("classifies unicode as compile and sets the unicode option flag", () => {
      const acc = buildAcc();
      const kind = RegexEngine.parseCompileOption(Type.atom("unicode"), acc);

      assert.equal(kind, "compile");
      assert.isTrue(acc.unicodeOption);
      assert.deepEqual(acc.engineOpts, {});
    });

    it("classifies bsr_anycrlf as dual and enables the engine opt", () => {
      const acc = buildAcc();

      const kind = RegexEngine.parseCompileOption(
        Type.atom("bsr_anycrlf"),
        acc,
      );

      assert.equal(kind, "dual");
      assert.deepEqual(acc.engineOpts, {bsr_anycrlf: true});
    });

    it("classifies bsr_unicode as dual and disables the bsr_anycrlf engine opt", () => {
      const acc = buildAcc();

      const kind = RegexEngine.parseCompileOption(
        Type.atom("bsr_unicode"),
        acc,
      );

      assert.equal(kind, "dual");
      assert.deepEqual(acc.engineOpts, {bsr_anycrlf: false});
    });

    it("classifies a newline tuple as dual and sets the newline type", () => {
      const acc = buildAcc();
      const option = Type.tuple([Type.atom("newline"), Type.atom("crlf")]);
      const kind = RegexEngine.parseCompileOption(option, acc);

      assert.equal(kind, "dual");
      assert.deepEqual(acc.engineOpts, {newline: "crlf"});
    });

    it("returns invalid for an unknown atom", () => {
      const kind = RegexEngine.parseCompileOption(Type.atom("bam"), buildAcc());

      assert.equal(kind, "invalid");
    });

    it("returns invalid for a newline tuple with an invalid type", () => {
      const option = Type.tuple([Type.atom("newline"), Type.atom("abc")]);
      const kind = RegexEngine.parseCompileOption(option, buildAcc());

      assert.equal(kind, "invalid");
    });

    it("returns invalid for a term that is not an atom or a tuple", () => {
      const kind = RegexEngine.parseCompileOption(Type.integer(1), buildAcc());

      assert.equal(kind, "invalid");
    });
  });

  describe("textFromLatin1Bytes()", () => {
    it("maps every byte to one JS char", () => {
      assert.equal(
        RegexEngine.textFromLatin1Bytes(new Uint8Array([0x61, 0xe9, 0xff])),
        "aéÿ",
      );
    });

    it("returns empty text for empty bytes", () => {
      assert.equal(RegexEngine.textFromLatin1Bytes(new Uint8Array([])), "");
    });
  });

  describe("utf16IndexToByteOffset()", () => {
    // a: 1 byte / 1 UTF-16 unit, é: 2 bytes / 1 unit, €: 3 bytes / 1 unit, 😀: 4 bytes / 2 units
    const text = "aé€😀";

    it("returns 0 for index 0", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset(text, 0), 0);
    });

    it("converts index after 1-byte code point", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset(text, 1), 1);
    });

    it("converts index after 2-byte code point", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset(text, 2), 3);
    });

    it("converts index after 3-byte code point", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset(text, 3), 6);
    });

    it("converts index after 4-byte code point", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset(text, 5), 10);
    });

    it("returns 0 for empty text", () => {
      assert.equal(RegexEngine.utf16IndexToByteOffset("", 0), 0);
    });
  });
});

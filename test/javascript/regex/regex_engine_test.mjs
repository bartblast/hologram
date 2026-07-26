"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexEngine from "../../../assets/js/regex/regex_engine.mjs";

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

"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Unicode from "../../../assets/js/erlang/unicode.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/unicode_test.exs
// Always update both together.

describe("Erlang_Unicode", () => {
  describe("characters_to_binary/1", () => {
    it("delegates to :unicode.characters_to_binary/3", () => {
      const input = Type.bitstring("全息图");
      const encoding = Type.atom("utf8");

      const result = Erlang_Unicode["characters_to_binary/1"](input);

      const expected = Erlang_Unicode["characters_to_binary/3"](
        input,
        encoding,
        encoding,
      );

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("characters_to_binary/3", () => {
    const characters_to_binary = Erlang_Unicode["characters_to_binary/3"];
    const utf8Atom = Type.atom("utf8");
    const latin1Atom = Type.atom("latin1");
    const utf16Big = Type.tuple([Type.atom("utf16"), Type.atom("big")]);
    const utf16Little = Type.tuple([Type.atom("utf16"), Type.atom("little")]);
    const utf32Big = Type.tuple([Type.atom("utf32"), Type.atom("big")]);
    const utf32Little = Type.tuple([Type.atom("utf32"), Type.atom("little")]);

    it("input is an empty list", () => {
      const result = characters_to_binary(Type.list(), utf8Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("input is a list of ASCII code points", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("abc");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a list of non-ASCII code points (Chinese)", () => {
      const input = Type.list([
        Type.integer(20840), // 全
        Type.integer(24687), // 息
        Type.integer(22270), // 图
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("全息图");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a binary bitstring", () => {
      const input = Type.bitstring("abc");

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      assert.deepStrictEqual(result, input);
    });

    it("input is a non-binary bitstring", () => {
      assertBoxedError(
        () =>
          characters_to_binary(Type.bitstring([1, 0, 1]), utf8Atom, utf8Atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("input is a list of binary bitstrings", () => {
      const input = Type.list([
        Type.bitstring("abc"),
        Type.bitstring("def"),
        Type.bitstring("ghi"),
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("abcdefghi");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a list of non-binary bitstrings", () => {
      const input = Type.list([
        Type.bitstring([1, 1, 0]),
        Type.bitstring([1, 0, 1]),
        Type.bitstring([0, 1, 1]),
      ]);

      assertBoxedError(
        () => characters_to_binary(input, utf8Atom, utf8Atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("input is a list of code points mixed with binary bitstrings", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.bitstring("bcd"),
        Type.integer(101), // e
        Type.bitstring("fgh"),
        Type.integer(105), // i
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("abcdefghi");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a list of elements of types other than a list or a bitstring", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => characters_to_binary(input, utf8Atom, utf8Atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("input is not a list or a bitstring", () => {
      assertBoxedError(
        () => characters_to_binary(Type.atom("abc"), utf8Atom, utf8Atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("input is a nested list", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.list([
          Type.integer(98), // b
          Type.list([
            Type.integer(99), // c
            Type.bitstring("def"),
            Type.integer(103), // g
          ]),
          Type.integer(104), // h
        ]),
        Type.integer(105), // i
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("abcdefghi");

      assert.deepStrictEqual(result, expected);
    });

    it("input contains invalid code points", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.bitstring("bcd"),
        // Max Unicode code point value is 1,114,112
        Type.integer(1114113),
        Type.bitstring("efg"),
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abcd"),
        Type.list([Type.integer(1114113), Type.bitstring("efg")]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("handles large input", () => {
      const str = "abcdefghij".repeat(100);
      const input = Type.bitstring(str);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring(str));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.integer(0x3042),
        Type.bitstring(" world"),
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring("hello \u3042 world");

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple on invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes(new Uint8Array([255, 255]));
      invalidBinary.text = false;

      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Type.list([invalidBinary]);
      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes(new Uint8Array([0xc0, 0x80]));
      invalidBinary.text = false;

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Type.list([invalidBinary]);
      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes(
        new Uint8Array([0xed, 0xa0, 0x80]),
      );
      invalidBinary.text = false;

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Type.list([invalidBinary]);
      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes(
        new Uint8Array([0xf5, 0x80, 0x80, 0x80]),
      );
      invalidBinary.text = false;

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Type.list([invalidBinary]);
      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple for truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes(
        new Uint8Array([0xe4, 0xb8]),
      );
      incompleteBinary.text = false;

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring("a"),
        incompleteBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple for single invalid binary not wrapped in a list", () => {
      const invalidBinary = Bitstring.fromBytes(new Uint8Array([255, 255]));
      invalidBinary.text = false;

      const result = characters_to_binary(invalidBinary, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple for single truncated binary not wrapped in a list", () => {
      // First byte of a 2-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes(new Uint8Array([0xc3]));
      incompleteBinary.text = false;

      const result = characters_to_binary(incompleteBinary, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring(""),
        incompleteBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple when invalid UTF-8 appears after valid prefix in binary", () => {
      const invalidBinary = Bitstring.fromBytes(
        new Uint8Array([0x41, 0xc3, 0x28]),
      );
      invalidBinary.text = false;

      const result = characters_to_binary(invalidBinary, utf8Atom, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xc3, 0x28]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Bitstring.fromBytes(new Uint8Array([0x41])),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple when truncated UTF-8 appears after valid prefix in binary", () => {
      const incompleteBinary = Bitstring.fromBytes(
        new Uint8Array([0x41, 0xc3]),
      );
      incompleteBinary.text = false;

      const result = characters_to_binary(incompleteBinary, utf8Atom, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xc3]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Bitstring.fromBytes(new Uint8Array([0x41])),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple when invalid UTF-8 appears after valid prefix in list", () => {
      const invalidBinary = Bitstring.fromBytes(
        new Uint8Array([0x42, 0xc3, 0x28]),
      );
      invalidBinary.text = false;

      const input = Type.list([Type.bitstring("A"), invalidBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xc3, 0x28]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        (() => {
          const prefix = Bitstring.fromBytes(new Uint8Array([0x41, 0x42]));
          prefix.text = "AB";
          return prefix;
        })(),
        Type.list([expectedRest]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple when truncated UTF-8 appears after valid prefix in list", () => {
      const incompleteBinary = Bitstring.fromBytes(
        new Uint8Array([0x42, 0xc3]),
      );
      incompleteBinary.text = false;

      const input = Type.list([Type.bitstring("A"), incompleteBinary]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xc3]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        (() => {
          const prefix = Bitstring.fromBytes(new Uint8Array([0x41, 0x42]));
          prefix.text = "AB";
          return prefix;
        })(),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-8 input to latin1 output", () => {
      const input = Type.bitstring("Å");

      const result = characters_to_binary(input, utf8Atom, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0xc5]));
      expected.text = "Å";

      assert.deepStrictEqual(result, expected);
    });

    it("converts latin1 input to UTF-8 output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0xc5]));

      const result = characters_to_binary(input, latin1Atom, utf8Atom);

      const expected = Type.bitstring("Å");

      assert.deepStrictEqual(result, expected);
    });

    it("rejects out-of-range codepoints when encoding to latin1 from binary", () => {
      const input = Type.bitstring("Ā"); // U+0100, beyond latin1 range

      const result = characters_to_binary(input, utf8Atom, latin1Atom);

      const emptyBitstring = Bitstring.fromBytes(new Uint8Array(0));
      emptyBitstring.text = "";

      const expected = Type.tuple([
        Type.atom("error"),
        emptyBitstring,
        Type.bitstring("Ā"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects out-of-range codepoints when encoding to latin1 from integer list", () => {
      const input = Type.list([Type.integer(256)]);

      const result = characters_to_binary(input, utf8Atom, latin1Atom);

      const emptyBitstring = Bitstring.fromBytes(new Uint8Array(0));
      emptyBitstring.text = "";

      // When an integer fails encoding, it's wrapped in a list
      const expected = Type.tuple([
        Type.atom("error"),
        emptyBitstring,
        Type.list([Type.list([Type.integer(256)])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("encodes valid prefix when encountering out-of-range codepoint for latin1", () => {
      const input = Type.list([
        Type.integer(65), // 'A'
        Type.integer(66), // 'B'
        Type.integer(256), // out of range
      ]);

      const result = characters_to_binary(input, utf8Atom, latin1Atom);

      const expectedPrefix = Bitstring.fromBytes(new Uint8Array([65, 66]));

      // First failing integer is wrapped, rest elements are not
      const expected = Type.tuple([
        Type.atom("error"),
        expectedPrefix,
        Type.list([Type.list([Type.integer(256)])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-8 input to UTF-16 output", () => {
      const input = Type.bitstring("A");

      const result = characters_to_binary(input, utf8Atom, utf16Big);

      const expected = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      expected.text = "A";

      assert.deepStrictEqual(result, expected);

      const littleEndian = characters_to_binary(input, utf8Atom, utf16Little);
      const expectedLittle = Bitstring.fromBytes(new Uint8Array([0x41, 0x00]));
      expectedLittle.text = "A";

      assert.deepStrictEqual(littleEndian, expectedLittle);
    });

    it("converts UTF-8 input to UTF-32 output", () => {
      const input = Type.bitstring("A");

      const result = characters_to_binary(input, utf8Atom, utf32Big);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      expected.text = "A";

      assert.deepStrictEqual(result, expected);

      const littleEndian = characters_to_binary(input, utf8Atom, utf32Little);
      const expectedLittle = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00, 0x00, 0x00]),
      );
      expectedLittle.text = "A";

      assert.deepStrictEqual(littleEndian, expectedLittle);
    });

    it("bare :utf16 atom defaults to big-endian", () => {
      const input = Type.bitstring("A");
      const utf16Atom = Type.atom("utf16");

      const result = characters_to_binary(input, utf8Atom, utf16Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      expected.text = "A";

      assert.deepStrictEqual(result, expected);
    });

    it("bare :utf32 atom defaults to big-endian", () => {
      const input = Type.bitstring("A");
      const utf32Atom = Type.atom("utf32");

      const result = characters_to_binary(input, utf8Atom, utf32Atom);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      expected.text = "A";

      assert.deepStrictEqual(result, expected);
    });

    it("explicit little-endian tuples match only little-endian", () => {
      const input = Type.bitstring("A");

      // UTF-16 little-endian should produce different bytes than big-endian
      const utf16LittleResult = characters_to_binary(
        input,
        utf8Atom,
        utf16Little,
      );
      const utf16BigResult = characters_to_binary(input, utf8Atom, utf16Big);

      const utf16LittleExpected = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00]),
      );
      utf16LittleExpected.text = "A";
      const utf16BigExpected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x41]),
      );
      utf16BigExpected.text = "A";

      assert.deepStrictEqual(utf16LittleResult, utf16LittleExpected);
      assert.deepStrictEqual(utf16BigResult, utf16BigExpected);

      // UTF-32 little-endian should produce different bytes than big-endian
      const utf32LittleResult = characters_to_binary(
        input,
        utf8Atom,
        utf32Little,
      );
      const utf32BigResult = characters_to_binary(input, utf8Atom, utf32Big);

      const utf32LittleExpected = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00, 0x00, 0x00]),
      );
      utf32LittleExpected.text = "A";
      const utf32BigExpected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      utf32BigExpected.text = "A";

      assert.deepStrictEqual(utf32LittleResult, utf32LittleExpected);
      assert.deepStrictEqual(utf32BigResult, utf32BigExpected);
    });

    // Input encoding tests
    it("converts UTF-16 BE input to UTF-8 output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("converts UTF-16 LE input to UTF-8 output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x41, 0x00]));
      const result = characters_to_binary(input, utf16Little, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("converts UTF-32 BE input to UTF-8 output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("converts UTF-32 LE input to UTF-8 output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Little, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("bare :utf16 input defaults to big-endian", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      const utf16Atom = Type.atom("utf16");
      const result = characters_to_binary(input, utf16Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("bare :utf32 input defaults to big-endian", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      const utf32Atom = Type.atom("utf32");
      const result = characters_to_binary(input, utf32Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("converts UTF-16 BE multi-byte character to UTF-8", () => {
      // U+4E2D (中) in UTF-16 BE
      const input = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("中"));
    });

    it("converts UTF-16 BE surrogate pair to UTF-8", () => {
      // U+1F600 (😀) in UTF-16 BE: high surrogate 0xD83D, low surrogate 0xDE00
      const input = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x3d, 0xde, 0x00]),
      );
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("😀"));
    });

    it("converts UTF-16 LE surrogate pair to UTF-8", () => {
      // U+1F600 (😀) in UTF-16 LE: high surrogate 0xD83D, low surrogate 0xDE00
      const input = Bitstring.fromBytes(
        new Uint8Array([0x3d, 0xd8, 0x00, 0xde]),
      );
      const result = characters_to_binary(input, utf16Little, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("😀"));
    });

    it("returns incomplete for truncated UTF-16 BE sequence (1 byte)", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x00]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0x00]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete for truncated UTF-16 BE sequence after valid prefix", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x41, 0x00]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0x00]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring("A"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete for truncated UTF-16 BE surrogate pair (3 bytes)", () => {
      // High surrogate 0xD83D + partial low surrogate
      const input = Bitstring.fromBytes(new Uint8Array([0xd8, 0x3d, 0xde]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x3d, 0xde]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error for invalid UTF-16 BE high surrogate alone", () => {
      // High surrogate without low surrogate (followed by regular char)
      const input = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x00, 0x00, 0x41]),
      );
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x00, 0x00, 0x41]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete for invalid UTF-16 BE high surrogate after valid prefix", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x41, 0xd8, 0x00]),
      );
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xd8, 0x00]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring("A"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error for invalid UTF-16 BE low surrogate alone", () => {
      // Low surrogate without high surrogate
      const input = Bitstring.fromBytes(new Uint8Array([0xdc, 0x00]));
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xdc, 0x00]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete for truncated UTF-32 BE sequence (3 bytes)", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x00, 0x00]));
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete for truncated UTF-32 BE sequence after valid prefix", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.bitstring("A"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error for invalid UTF-32 BE codepoint beyond U+10FFFF", () => {
      // U+110000 (beyond valid Unicode range)
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x11, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x11, 0x00, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error for invalid UTF-32 BE codepoint after valid prefix", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41, 0x00, 0x11, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x11, 0x00, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("A"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error for UTF-32 BE surrogate range codepoint", () => {
      // U+D800 (surrogate range, invalid in UTF-32)
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0xd8, 0x00]),
      );
      const result = characters_to_binary(input, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0xd8, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts multiple UTF-16 BE characters to UTF-8", () => {
      // "AB" in UTF-16 BE
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x41, 0x00, 0x42]),
      );
      const result = characters_to_binary(input, utf16Big, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("AB"));
    });

    it("converts UTF-16 BE input to latin1 output", () => {
      // "A" in UTF-16 BE to latin1
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      const result = characters_to_binary(input, utf16Big, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x41]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 LE input to UTF-16 BE output", () => {
      // "A" from UTF-32 LE to UTF-16 BE
      const input = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Little, utf16Big);

      const expected = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));

      assert.deepStrictEqual(result, expected);
    });

    // Comprehensive input/output encoding combinations
    it("converts latin1 input to latin1 output (identity)", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0xc5])); // Å in latin1
      const result = characters_to_binary(input, latin1Atom, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0xc5]));
      // Don't set text for non-UTF-8 encodings

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-8 input to UTF-8 output (identity)", () => {
      const input = Type.bitstring("Å");
      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      assert.deepStrictEqual(result, input);
    });

    it("converts latin1 input to UTF-8 output (all latin1 range)", () => {
      // Test with latin1-only characters (0xA0-0xFF range)
      const input = Bitstring.fromBytes(new Uint8Array([0xa0, 0xc5, 0xff]));
      const result = characters_to_binary(input, latin1Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("\u00A0Å\u00FF"));
    });

    it("converts latin1 input to UTF-16 BE output", () => {
      // latin1 Å (0xC5) → UTF-16 BE
      const input = Bitstring.fromBytes(new Uint8Array([0xc5]));
      const result = characters_to_binary(input, latin1Atom, utf16Big);

      // U+00C5 in UTF-16 BE
      const expected = Bitstring.fromBytes(new Uint8Array([0x00, 0xc5]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts latin1 input to UTF-16 LE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0xc5]));
      const result = characters_to_binary(input, latin1Atom, utf16Little);

      // U+00C5 in UTF-16 LE
      const expected = Bitstring.fromBytes(new Uint8Array([0xc5, 0x00]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts latin1 input to UTF-32 BE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0xc5]));
      const result = characters_to_binary(input, latin1Atom, utf32Big);

      // U+00C5 in UTF-32 BE
      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0xc5]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts latin1 input to UTF-32 LE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0xc5]));
      const result = characters_to_binary(input, latin1Atom, utf32Little);

      // U+00C5 in UTF-32 LE
      const expected = Bitstring.fromBytes(
        new Uint8Array([0xc5, 0x00, 0x00, 0x00]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 BE input to UTF-16 LE output", () => {
      // U+4E2D (中) in UTF-16 BE → UTF-16 LE
      const input = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));
      const result = characters_to_binary(input, utf16Big, utf16Little);

      const expected = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 BE input to UTF-32 BE output", () => {
      // U+4E2D (中) in UTF-16 BE → UTF-32 BE
      const input = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));
      const result = characters_to_binary(input, utf16Big, utf32Big);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 BE input to UTF-32 LE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));
      const result = characters_to_binary(input, utf16Big, utf32Little);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x2d, 0x4e, 0x00, 0x00]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 BE input to latin1 output (ASCII subset)", () => {
      // U+0041 (A) in UTF-16 BE → latin1
      const input = Bitstring.fromBytes(new Uint8Array([0x00, 0x41]));
      const result = characters_to_binary(input, utf16Big, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x41]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 LE input to latin1 output (ASCII subset)", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x41, 0x00]));
      const result = characters_to_binary(input, utf16Little, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x41]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 LE input to UTF-16 BE output", () => {
      // U+4E2D (中) in UTF-16 LE → UTF-16 BE
      const input = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));
      const result = characters_to_binary(input, utf16Little, utf16Big);

      const expected = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 LE input to UTF-32 BE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));
      const result = characters_to_binary(input, utf16Little, utf32Big);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-16 LE input to UTF-32 LE output", () => {
      const input = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));
      const result = characters_to_binary(input, utf16Little, utf32Little);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x2d, 0x4e, 0x00, 0x00]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 BE input to UTF-16 BE output", () => {
      // U+4E2D (中) in UTF-32 BE → UTF-16 BE
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );
      const result = characters_to_binary(input, utf32Big, utf16Big);

      const expected = Bitstring.fromBytes(new Uint8Array([0x4e, 0x2d]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 BE input to UTF-16 LE output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );
      const result = characters_to_binary(input, utf32Big, utf16Little);

      const expected = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 BE input to UTF-32 LE output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );
      const result = characters_to_binary(input, utf32Big, utf32Little);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x2d, 0x4e, 0x00, 0x00]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 BE input to latin1 output (ASCII subset)", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x00, 0x41]),
      );
      const result = characters_to_binary(input, utf32Big, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x41]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 LE input to UTF-16 LE output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x2d, 0x4e, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Little, utf16Little);

      const expected = Bitstring.fromBytes(new Uint8Array([0x2d, 0x4e]));

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 LE input to UTF-32 BE output", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x2d, 0x4e, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Little, utf32Big);

      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x00, 0x4e, 0x2d]),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("converts UTF-32 LE input to latin1 output (ASCII subset)", () => {
      const input = Bitstring.fromBytes(
        new Uint8Array([0x41, 0x00, 0x00, 0x00]),
      );
      const result = characters_to_binary(input, utf32Little, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0x41]));

      assert.deepStrictEqual(result, expected);
    });

    it("treats :unicode input encoding like :utf8", () => {
      const unicodeAtom = Type.atom("unicode");
      const input = Bitstring.fromBytes(new Uint8Array([0x41, 0xff]));
      input.text = false;

      const result = characters_to_binary(input, unicodeAtom, utf8Atom);

      const expectedRest = Bitstring.fromBytes(new Uint8Array([0xff]));
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Bitstring.fromBytes(new Uint8Array([0x41])),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("treats :unicode output encoding like :utf8", () => {
      const unicodeAtom = Type.atom("unicode");
      const input = Type.bitstring("A");

      const result = characters_to_binary(input, utf8Atom, unicodeAtom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("treats :unicode input and output like :utf8", () => {
      const unicodeAtom = Type.atom("unicode");
      const input = Type.bitstring("A");

      const result = characters_to_binary(input, unicodeAtom, unicodeAtom);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("encodes latin1 integer list to UTF-8 when output is utf8", () => {
      const input = Type.list([Type.integer(255)]);

      const result = characters_to_binary(input, latin1Atom, utf8Atom);

      assert.deepStrictEqual(result, Type.bitstring("\u00FF"));
    });

    it("encodes latin1 integer list to latin1 when output is latin1", () => {
      const input = Type.list([Type.integer(255)]);

      const result = characters_to_binary(input, latin1Atom, latin1Atom);

      const expected = Bitstring.fromBytes(new Uint8Array([0xff]));
      expected.text = false;

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple for UTF-16 surrogate codepoint in list", () => {
      const input = Type.list([Type.integer(0xd800)]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("error"),
        (() => {
          const emptyPrefix = Bitstring.fromBytes(new Uint8Array(0));
          emptyPrefix.text = "";
          return emptyPrefix;
        })(),
        Type.list([Type.integer(0xd800)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-32 codepoint with high byte >= 0x80 (above U+10FFFF)", () => {
      // Invalid UTF-32: 0x80000000 is above Unicode maximum U+10FFFF
      // Big-endian representation of 0x80000000
      const invalidUtf32 = Bitstring.fromBytes(
        new Uint8Array([0x80, 0x00, 0x00, 0x00]),
      );

      const result = characters_to_binary(invalidUtf32, utf32Big, utf8Atom);

      const expectedRest = Bitstring.fromBytes(
        new Uint8Array([0x80, 0x00, 0x00, 0x00]),
      );
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("encodes emoji (supplementary plane) to UTF-16 big-endian with surrogate pairs", () => {
      // U+1F600 (😀) requires surrogate pair in UTF-16
      const emoji = Type.bitstring("😀");

      const result = characters_to_binary(emoji, utf8Atom, utf16Big);

      // High surrogate: 0xD83D, Low surrogate: 0xDE00
      const expected = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x3d, 0xde, 0x00]),
      );
      expected.text = "😀";

      assert.deepStrictEqual(result, expected);
    });

    it("encodes emoji (supplementary plane) to UTF-16 little-endian with surrogate pairs", () => {
      // U+1F600 (😀) requires surrogate pair in UTF-16
      const emoji = Type.bitstring("😀");

      const result = characters_to_binary(emoji, utf8Atom, utf16Little);

      // Little-endian: low byte first for each 16-bit unit
      // High surrogate: 0xD83D -> 0x3D, 0xD8
      // Low surrogate: 0xDE00 -> 0x00, 0xDE
      const expected = Bitstring.fromBytes(
        new Uint8Array([0x3d, 0xd8, 0x00, 0xde]),
      );
      expected.text = "😀";

      assert.deepStrictEqual(result, expected);
    });

    it("encodes multiple emoji characters to UTF-16 big-endian", () => {
      // Two emoji: 😀 (U+1F600) and 🎉 (U+1F389)
      const emojis = Type.bitstring("😀🎉");

      const result = characters_to_binary(emojis, utf8Atom, utf16Big);

      // 😀: 0xD83D 0xDE00
      // 🎉: 0xD83C 0xDF89
      const expected = Bitstring.fromBytes(
        new Uint8Array([0xd8, 0x3d, 0xde, 0x00, 0xd8, 0x3c, 0xdf, 0x89]),
      );
      expected.text = "😀🎉";

      assert.deepStrictEqual(result, expected);
    });

    it("encodes BMP character mixed with emoji to UTF-16 big-endian", () => {
      // 'A' (U+0041) is BMP, 😀 (U+1F600) is supplementary
      const mixed = Type.bitstring("A😀");

      const result = characters_to_binary(mixed, utf8Atom, utf16Big);

      // A: 0x0041 (2 bytes)
      // 😀: 0xD83D 0xDE00 (4 bytes)
      const expected = Bitstring.fromBytes(
        new Uint8Array([0x00, 0x41, 0xd8, 0x3d, 0xde, 0x00]),
      );
      expected.text = "A😀";

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bom_to_encoding/1", () => {
    const fun = Erlang_Unicode["bom_to_encoding/1"];

    it("detects UTF-8 BOM", () => {
      const input = Bitstring.fromBytes([0xef, 0xbb, 0xbf, 0x41]);

      const result = fun(input);

      const expected = Type.tuple([Type.atom("utf8"), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });

    it("detects UTF-16 BOMs", () => {
      const bigInput = Bitstring.fromBytes([0xfe, 0xff, 0x00, 0x41]);
      const littleInput = Bitstring.fromBytes([0xff, 0xfe, 0x41, 0x00]);

      const bigResult = fun(bigInput);
      const littleResult = fun(littleInput);

      const bigExpected = Type.tuple([
        Type.tuple([Type.atom("utf16"), Type.atom("big")]),
        Type.integer(2),
      ]);
      const littleExpected = Type.tuple([
        Type.tuple([Type.atom("utf16"), Type.atom("little")]),
        Type.integer(2),
      ]);

      assert.deepStrictEqual(bigResult, bigExpected);
      assert.deepStrictEqual(littleResult, littleExpected);
    });

    it("detects UTF-32 BOMs", () => {
      const bigInput = Bitstring.fromBytes([0x00, 0x00, 0xfe, 0xff, 0x00]);
      const littleInput = Bitstring.fromBytes([0xff, 0xfe, 0x00, 0x00, 0x00]);

      const bigResult = fun(bigInput);
      const littleResult = fun(littleInput);

      const bigExpected = Type.tuple([
        Type.tuple([Type.atom("utf32"), Type.atom("big")]),
        Type.integer(4),
      ]);
      const littleExpected = Type.tuple([
        Type.tuple([Type.atom("utf32"), Type.atom("little")]),
        Type.integer(4),
      ]);

      assert.deepStrictEqual(bigResult, bigExpected);
      assert.deepStrictEqual(littleResult, littleExpected);
    });

    it("defaults to latin1 without BOM", () => {
      const result = fun(Type.bitstring("A"));

      const expected = Type.tuple([Type.atom("latin1"), Type.integer(0)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("characters_to_list/1", () => {
    const fun = Erlang_Unicode["characters_to_list/1"];

    it("converts binary to list of codepoints", () => {
      const result = fun(Type.bitstring("abc"));

      const expected = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts binary with non-ASCII characters (Chinese)", () => {
      const result = fun(Type.bitstring("全息图"));

      const expected = Type.list([
        Type.integer(20840), // 全
        Type.integer(24687), // 息
        Type.integer(22270), // 图
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts list of codepoints to list of codepoints", () => {
      const input = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, input);
    });

    it("converts list of binaries", () => {
      const input = Type.list([
        Type.bitstring("abc"),
        Type.bitstring("def"),
        Type.bitstring("ghi"),
      ]);

      const result = fun(input);

      const expected = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
        Type.integer(100), // d
        Type.integer(101), // e
        Type.integer(102), // f
        Type.integer(103), // g
        Type.integer(104), // h
        Type.integer(105), // i
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts mixed list of codepoints and binaries", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.bitstring("bcd"),
        Type.integer(101), // e
        Type.bitstring("fgh"),
        Type.integer(105), // i
      ]);

      const result = fun(input);

      const expected = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
        Type.integer(100), // d
        Type.integer(101), // e
        Type.integer(102), // f
        Type.integer(103), // g
        Type.integer(104), // h
        Type.integer(105), // i
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("handles nested lists", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.list([
          Type.integer(98), // b
          Type.list([
            Type.integer(99), // c
            Type.bitstring("def"),
            Type.integer(103), // g
          ]),
          Type.integer(104), // h
        ]),
        Type.integer(105), // i
      ]);

      const result = fun(input);

      const expected = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
        Type.integer(100), // d
        Type.integer(101), // e
        Type.integer(102), // f
        Type.integer(103), // g
        Type.integer(104), // h
        Type.integer(105), // i
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty binary", () => {
      const result = fun(Type.bitstring(""));

      assert.deepStrictEqual(result, Type.list());
    });

    it("handles empty list", () => {
      const result = fun(Type.list());

      assert.deepStrictEqual(result, Type.list());
    });

    it("handles deeply nested lists", () => {
      const input = Type.list([
        Type.list([Type.list([Type.bitstring("abc")])]),
      ]);

      const result = fun(input);

      const expected = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("handles large input", () => {
      const str = "abcdefghij".repeat(100);
      const largeInput = Type.bitstring(str);

      const result = fun(largeInput);

      const expected = Type.list(
        Array.from(str).map((char) => Type.integer(char.codePointAt(0))),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.integer(0x3042), // Hiragana A
        Type.bitstring(" world"),
      ]);

      const result = fun(input);

      const expected = Type.list([
        Type.integer(104), // h
        Type.integer(101), // e
        Type.integer(108), // l
        Type.integer(108), // l
        Type.integer(111), // o
        Type.integer(32), // space
        Type.integer(0x3042), // Hiragana A
        Type.integer(32), // space
        Type.integer(119), // w
        Type.integer(111), // o
        Type.integer(114), // r
        Type.integer(108), // l
        Type.integer(100), // d
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple on invalid UTF-8 in binary", () => {
      const input = Type.list([
        Type.bitstring("abc"),
        Bitstring.fromBytes([255, 255]),
      ]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
        Type.list([expectedRest]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const input = Type.list([
        Type.bitstring("a"),
        Bitstring.fromBytes([0xc0, 0x80]),
      ]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xc0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        Type.list([expectedRest]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const input = Type.list([
        Type.bitstring("a"),
        Bitstring.fromBytes([0xed, 0xa0, 0x80]),
      ]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xed, 0xa0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        Type.list([expectedRest]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const input = Type.list([
        Type.bitstring("a"),
        Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]),
      ]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        Type.list([expectedRest]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple for truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const input = Type.list([
        Type.bitstring("a"),
        Bitstring.fromBytes([0xe4, 0xb8]),
      ]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xe4, 0xb8]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.list([Type.integer(97)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple for single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list(),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns incomplete tuple for single truncated binary not wrapped in a list", () => {
      // First byte of a 2-byte sequence (incomplete)
      const input = Bitstring.fromBytes([0xc3]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xc3]);

      const expected = Type.tuple([
        Type.atom("incomplete"),
        Type.list(),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("returns error tuple on invalid code point (above max)", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        Type.list([Type.integer(0x110000)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list(),
        Type.list([Type.integer(-1)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  // NFC_BINARY: Canonical composition form
  // Composes character sequences into their canonical composed form (e.g., a + ◌̊ → å)
  // This suite contains the full baseline test coverage inherited by all normalization functions
  describe("characters_to_nfc_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfc_binary/1"];

    // === NFC-SPECIFIC TESTS ===
    // Tests unique to canonical composition behavior

    it("normalizes combining characters to NFC", () => {
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

    // === COMMON STRUCTURAL TESTS ===
    // Tests shared across all normalization forms: handling of various input structures

    it("handles already normalized text", () => {
      const input = Type.bitstring("åäö");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("åäö"));
    });

    it("normalizes nested chardata", () => {
      const input = Type.list([
        Type.bitstring("abc.."),
        Type.list([Type.bitstring("a"), Type.integer(0x030a)]),
        Type.bitstring("a"),
        Type.list([Type.integer(0x0308)]),
        Type.bitstring("o"),
        Type.integer(0x0308),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("abc..åäö"));
    });

    it("handles empty binary", () => {
      const input = Type.bitstring("");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles empty list", () => {
      const input = Type.list();
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles deeply nested lists", () => {
      const input = Type.list([
        Type.list([Type.list([Type.bitstring("a"), Type.integer(0x030a)])]),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

    it("handles multiple combining marks", () => {
      const input = Type.list([
        Type.bitstring("o"),
        Type.integer(0x0308), // Combining diaeresis
        Type.integer(0x0304), // Combining macron
      ]);

      const result = fun(input);

      // Normalized form combines these in canonical order
      assert.deepStrictEqual(result, Type.bitstring("ȫ"));
    });

    it("handles large input", () => {
      const largeInput = "abcdefghij".repeat(100);
      const input = Type.bitstring(largeInput);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(largeInput));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.bitstring("a"),
        Type.integer(0x030a),
        Type.bitstring(" world"),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("hello å world"));
    });

    it("preserves non-combining characters", () => {
      const input = Type.list([
        Type.integer(0x3042), // Hiragana A
        Type.integer(0x3044), // Hiragana I
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("あい"));
    });

    it("rejects invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xc0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xed, 0xa0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes([0xe4, 0xb8]);

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xe4, 0xb8]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON ERROR HANDLING TESTS ===
    // Tests for invalid inputs that raise ArgumentError

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point before normalization", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point after normalization", () => {
      const input = Type.list([
        Type.bitstring("a"),
        Type.integer(0x030a),
        Type.integer(0x110000),
      ]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });
  });

  // NFC_LIST: Output format variation of NFC
  // Tests: same structural and normalization behaviors as NFC_BINARY, but returning a list instead of binary
  describe("characters_to_nfc_list/1", () => {
    const fun = Erlang_Unicode["characters_to_nfc_list/1"];

    it("normalizes combining characters to NFC", () => {
      const result = fun(Type.list([Type.integer(97), Type.integer(0x030a)]));
      const expected = Type.list([Type.integer(229)]); // å

      assert.deepStrictEqual(result, expected);
    });

    it("handles already normalized text", () => {
      const result = fun(Type.list([Type.integer(229)]));
      const expected = Type.list([Type.integer(229)]);

      assert.deepStrictEqual(result, expected);
    });

    it("normalizes nested chardata", () => {
      const result = fun(
        Type.list([
          Type.bitstring("abc..a"),
          Type.integer(0x030a), // combining ring above
          Type.list([Type.integer(97)]), // a
          Type.integer(0x0308), // combining diaeresis
          Type.bitstring("o"),
          Type.integer(0x0308), // combining diaeresis
        ]),
      );

      const expected = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
        Type.integer(46), // .
        Type.integer(46), // .
        Type.integer(229), // å (a + ring composed)
        Type.integer(228), // ä (a + diaeresis composed)
        Type.integer(246), // ö (o + diaeresis composed)
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty binary", () => {
      const result = fun(Type.bitstring(""));

      assert.deepStrictEqual(result, Type.list());
    });

    it("handles empty list", () => {
      const result = fun(Type.list());

      assert.deepStrictEqual(result, Type.list());
    });

    it("handles deeply nested lists", () => {
      const result = fun(
        Type.list([
          Type.list([Type.list([Type.integer(97), Type.integer(0x030a)])]),
        ]),
      );

      const expected = Type.list([Type.integer(229)]); // å

      assert.deepStrictEqual(result, expected);
    });

    it("handles multiple combining marks", () => {
      const result = fun(
        Type.list([
          Type.integer(111),
          Type.integer(0x0308),
          Type.integer(0x0304),
        ]),
      );

      // Normalized form combines these in canonical order
      const expected = Type.list([Type.integer(0x022b)]); // ȫ

      assert.deepStrictEqual(result, expected);
    });

    it("handles large input", () => {
      const largeInput = [];

      for (let i = 0; i < 100; i++) {
        largeInput.push(
          Type.integer(97), // a
          Type.integer(98), // b
          Type.integer(99), // c
          Type.integer(100), // d
          Type.integer(101), // e
          Type.integer(102), // f
          Type.integer(103), // g
          Type.integer(104), // h
          Type.integer(105), // i
          Type.integer(106), // j
        );
      }

      const result = fun(Type.list(largeInput));
      const expected = Type.list(largeInput);

      assert.deepStrictEqual(result, expected);
    });

    it("handles mixed ASCII and Unicode", () => {
      const result = fun(
        Type.list([
          Type.bitstring("hello"),
          Type.bitstring(" "),
          Type.list([Type.integer(97), Type.integer(0x030a)]), // [?a, 0x030A]
          Type.bitstring(" world"),
        ]),
      );

      const expected = Type.list([
        Type.integer(104), // h
        Type.integer(101), // e
        Type.integer(108), // l
        Type.integer(108), // l
        Type.integer(111), // o
        Type.integer(32), // space
        Type.integer(229), // å
        Type.integer(32), // space
        Type.integer(119), // w
        Type.integer(111), // o
        Type.integer(114), // r
        Type.integer(108), // l
        Type.integer(100), // d
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("preserves non-combining characters", () => {
      const result = fun(
        Type.list([Type.integer(0x3042), Type.integer(0x3044)]),
      );

      const expected = Type.list([Type.integer(0x3042), Type.integer(0x3044)]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);
      const input = Type.list([Type.bitstring("a"), invalidBinary]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xc0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xed, 0xa0, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes([0xe4, 0xb8]);

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([0xe4, 0xb8]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list([Type.integer(97)]),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);
      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.list(),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point before normalization", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point after normalization", () => {
      const input = Type.list([
        Type.list([Type.integer(97), Type.integer(0x030a)]),
        Type.integer(0x110000),
      ]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });
  });

  // NFD_BINARY: Canonical decomposition form
  // Decomposes characters into their canonical decomposed form (e.g., å → a + ◌̊)
  // Inherits all structural and error handling tests from NFC_BINARY
  describe("characters_to_nfd_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfd_binary/1"];

    // === NFD-SPECIFIC TESTS ===
    // Tests unique to canonical decomposition behavior

    it("decomposes combining characters to NFD", () => {
      const input = Type.bitstring("å");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("handles already decomposed text", () => {
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, input);
    });

    it("decomposes nested chardata", () => {
      const input = Type.list([
        Type.bitstring("abc.."),
        Type.list([Type.bitstring("a"), Type.integer(0x030a)]),
        Type.bitstring("a"),
        Type.list([Type.integer(0x0308)]),
        Type.bitstring("o"),
        Type.integer(0x0308),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(
        result,
        Type.bitstring("abc..a\u030aa\u0308o\u0308"),
      );
    });

    it("handles multiple combining marks", () => {
      const input = Type.list([
        Type.bitstring("o"),
        Type.integer(0x0308), // Combining diaeresis
        Type.integer(0x0304), // Combining macron
      ]);

      const result = fun(input);

      // NFD preserves combining marks in canonical order
      assert.deepStrictEqual(result, Type.bitstring("o\u0308\u0304"));
    });

    it("normalizes prefix in error tuple", () => {
      // Prefix contains precomposed "å" (U+00E5) which should be normalized to "a" + U+030A
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("å"), invalidBinary]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);
      expectedRest.text = false;

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a\u030a"),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON STRUCTURAL TESTS ===
    // Inherited from NFC_BINARY

    it("handles empty binary", () => {
      const input = Type.bitstring("");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles empty list", () => {
      const input = Type.list();
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles deeply nested lists", () => {
      const input = Type.list([Type.list([Type.list([Type.bitstring("å")])])]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("handles large input", () => {
      const largeInput = "abcdefghij".repeat(100);
      const input = Type.bitstring(largeInput);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(largeInput));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.bitstring("å"),
        Type.bitstring(" world"),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("hello a\u030a world"));
    });

    it("preserves non-combining characters", () => {
      const input = Type.list([
        Type.integer(0x3042), // Hiragana A
        Type.integer(0x3044), // Hiragana I
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("あい"));
    });

    // === COMMON UTF-8 VALIDATION TESTS ===
    // Inherited from NFC_BINARY

    it("rejects invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes([0xe4, 0xb8]);

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        incompleteBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON ERROR HANDLING TESTS ===
    // Inherited from NFC_BINARY

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point before normalization", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point after normalization", () => {
      const input = Type.list([Type.bitstring("å"), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });
  });

  // NFKC_BINARY: Compatibility composition form
  // Composes characters with compatibility equivalence (e.g., ﬁ → fi, Ａ → A) then canonical composition
  // Inherits all structural and error handling tests from NFC_BINARY
  describe("characters_to_nfkc_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfkc_binary/1"];

    // === NFKC-SPECIFIC TESTS ===
    // Tests unique to compatibility composition: ligatures, width variants, compatibility characters

    it("normalizes combining characters to NFKC (composition)", () => {
      // NFKC performs composition like NFC
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

    it("normalizes compatibility characters", () => {
      // NFKC normalizes compatibility characters like ℌ (U+210C) to H (U+0048)
      const input = Type.bitstring("\u210C"); // ℌ SCRIPT CAPITAL H

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("H"));
    });

    it("normalizes ligatures", () => {
      // NFKC normalizes ligatures like ﬁ (U+FB01) to fi (U+0066 U+0069)
      const input = Type.bitstring("\uFB01"); // ﬁ LATIN SMALL LIGATURE FI

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("fi"));
    });

    it("normalizes width variants", () => {
      // NFKC normalizes fullwidth forms like Ａ (U+FF21) to A (U+0041)
      const input = Type.bitstring("\uFF21"); // Ａ FULLWIDTH LATIN CAPITAL LETTER A

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    it("normalizes fullwidth numbers", () => {
      // NFKC normalizes fullwidth digits to ASCII: ３２ (U+FF13, U+FF12) -> 32
      const input = Type.list([
        Type.integer(0xff13), // ３ FULLWIDTH DIGIT THREE
        Type.integer(0xff12), // ２ FULLWIDTH DIGIT TWO
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("32"));
    });

    // === COMMON STRUCTURAL TESTS ===
    // Inherited from NFC_BINARY

    it("handles already normalized text", () => {
      const input = Type.bitstring("åäö");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("åäö"));
    });

    it("normalizes nested chardata", () => {
      const input = Type.list([
        Type.bitstring("abc.."),
        Type.list([Type.bitstring("a"), Type.integer(0x030a)]),
        Type.bitstring("a"),
        Type.list([Type.integer(0x0308)]),
        Type.bitstring("o"),
        Type.integer(0x0308),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("abc..åäö"));
    });

    it("handles empty binary", () => {
      const input = Type.bitstring("");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles empty list", () => {
      const input = Type.list();
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles deeply nested lists", () => {
      const input = Type.list([
        Type.list([Type.list([Type.bitstring("a"), Type.integer(0x030a)])]),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

    it("handles multiple combining marks", () => {
      const input = Type.list([
        Type.bitstring("o"),
        Type.integer(0x0308), // Combining diaeresis
        Type.integer(0x0304), // Combining macron
      ]);

      const result = fun(input);

      // Normalized form combines these in canonical order
      assert.deepStrictEqual(result, Type.bitstring("ȫ"));
    });

    it("handles large input", () => {
      const largeInput = "abcdefghij".repeat(100);
      const input = Type.bitstring(largeInput);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(largeInput));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.bitstring("a"),
        Type.integer(0x030a),
        Type.bitstring(" world"),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("hello å world"));
    });

    it("preserves non-combining characters", () => {
      const input = Type.list([
        Type.integer(0x3042), // Hiragana A
        Type.integer(0x3044), // Hiragana I
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("あい"));
    });

    // === COMMON UTF-8 VALIDATION TESTS ===
    // Inherited from NFC_BINARY

    it("rejects invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes([0xe4, 0xb8]);

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        incompleteBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON ERROR HANDLING TESTS ===
    // Inherited from NFC_BINARY

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point before normalization", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point after normalization", () => {
      const input = Type.list([
        Type.bitstring("a"),
        Type.integer(0x030a),
        Type.integer(0x110000),
      ]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });
  });

  // NFKD_BINARY: Compatibility decomposition form
  // Decomposes characters with compatibility equivalence (e.g., ﬁ → fi, Ａ → A) then canonical decomposition
  // Inherits all structural and error handling tests from NFC_BINARY
  describe("characters_to_nfkd_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfkd_binary/1"];

    // === NFKD-SPECIFIC TESTS ===
    // Tests unique to compatibility decomposition: ligatures, width variants, compatibility characters

    it("decomposes already normalized precomposed characters", () => {
      // Input: precomposed "å" (U+00E5)
      // NFKD: decomposes to "a" + combining ring above (U+0061 + U+030A)
      const input = Type.bitstring("å");

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("normalizes compatibility characters", () => {
      // NFKD normalizes compatibility characters like ℌ (U+210C) to H (U+0048)
      const input = Type.bitstring("\u210C"); // ℌ DOUBLE-STRUCK CAPITAL H

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("H"));
    });

    it("normalizes ligatures", () => {
      // NFKD normalizes ligatures like ﬁ (U+FB01) to fi (U+0066 U+0069)
      const input = Type.bitstring("\uFB01"); // ﬁ LATIN SMALL LIGATURE FI

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("fi"));
    });

    it("normalizes width variants", () => {
      // NFKD normalizes fullwidth forms like Ａ (U+FF21) to A (U+0041)
      const input = Type.bitstring("\uFF21"); // Ａ FULLWIDTH LATIN CAPITAL LETTER A

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("A"));
    });

    // === COMMON STRUCTURAL TESTS ===
    // Inherited from NFC_BINARY

    it("handles already decomposed text", () => {
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, input);
    });

    it("decomposes nested chardata", () => {
      const input = Type.list([
        Type.bitstring("abc.."),
        Type.list([Type.bitstring("a"), Type.integer(0x030a)]),
        Type.bitstring("a"),
        Type.list([Type.integer(0x0308)]),
        Type.bitstring("o"),
        Type.integer(0x0308),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(
        result,
        Type.bitstring("abc..a\u030aa\u0308o\u0308"),
      );
    });

    it("handles empty binary", () => {
      const input = Type.bitstring("");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles empty list", () => {
      const input = Type.list();
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("handles deeply nested lists", () => {
      const input = Type.list([Type.list([Type.list([Type.bitstring("å")])])]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("handles multiple combining marks", () => {
      const input = Type.list([
        Type.bitstring("o"),
        Type.integer(0x0308), // Combining diaeresis
        Type.integer(0x0304), // Combining macron
      ]);

      const result = fun(input);

      // NFKD preserves combining marks in canonical order
      assert.deepStrictEqual(result, Type.bitstring("o\u0308\u0304"));
    });

    it("handles large input", () => {
      const largeInput = "abcdefghij".repeat(100);
      const input = Type.bitstring(largeInput);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(largeInput));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring(" "),
        Type.bitstring("å"),
        Type.bitstring(" world"),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("hello a\u030a world"));
    });

    it("preserves non-combining characters", () => {
      const input = Type.list([
        Type.integer(0x3042), // Hiragana A
        Type.integer(0x3044), // Hiragana I
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("あい"));
    });

    it("normalizes prefix in error tuple", () => {
      // Prefix contains precomposed "å" (U+00E5) which should be normalized to "a" + U+030A
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("å"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a\u030a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON UTF-8 VALIDATION TESTS ===
    // Inherited from NFC_BINARY

    it("rejects invalid UTF-8 in binary", () => {
      const invalidBinary = Bitstring.fromBytes([255, 255]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong UTF-8 sequence in binary", () => {
      // Overlong encoding of NUL: 0xC0 0x80 (invalid)
      const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate range in binary", () => {
      // CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code points above U+10FFFF in binary", () => {
      // Leader 0xF5 starts sequences above Unicode max (invalid)
      const invalidBinary = Bitstring.fromBytes([0xf5, 0x80, 0x80, 0x80]);

      const input = Type.list([Type.bitstring("a"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects truncated UTF-8 sequence", () => {
      // First two bytes of a 3-byte sequence (incomplete)
      const incompleteBinary = Bitstring.fromBytes([0xe4, 0xb8]);

      const input = Type.list([Type.bitstring("a"), incompleteBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("a"),
        incompleteBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects single invalid binary not wrapped in a list", () => {
      const input = Bitstring.fromBytes([255, 255]);

      const result = fun(input);

      const expectedRest = Bitstring.fromBytes([255, 255]);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring(""),
        expectedRest,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // === COMMON ERROR HANDLING TESTS ===
    // Inherited from NFC_BINARY

    it("raises ArgumentError when input is not a list or a bitstring", () => {
      assertBoxedError(
        () => fun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input is a non-binary bitstring", () => {
      const input = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError when input list contains invalid types", () => {
      const input = Type.list([Type.float(123.45), Type.atom("abc")]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point before normalization", () => {
      const input = Type.list([Type.integer(97), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on invalid code point after normalization", () => {
      const input = Type.list([Type.bitstring("å"), Type.integer(0x110000)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError on negative integer code point", () => {
      const input = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => fun(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });
  });
});

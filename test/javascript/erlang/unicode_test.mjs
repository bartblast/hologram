"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Unicode from "../../../assets/js/erlang/unicode.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
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

    // This is temporary, until the related TODO is implemented.
    it("input encoding is different than :utf8", () => {
      assert.throw(
        () => characters_to_binary(Type.list(), Type.atom("utf16"), utf8Atom),
        HologramInterpreterError,
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    });

    // This is temporary, until the related TODO is implemented.
    it("output encoding is different than :utf8", () => {
      assert.throw(
        () => characters_to_binary(Type.list(), utf8Atom, Type.atom("utf16")),
        HologramInterpreterError,
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    });
  });

  describe("characters_to_list/1", () => {
    const fun = Erlang_Unicode["characters_to_list/1"];

    it("UTF8 binary", () => {
      const result = fun(Type.bitstring("全息图"));

      const expected = Type.list([
        Type.integer(20840),
        Type.integer(24687),
        Type.integer(22270),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("list of UTF8 binaries", () => {
      const result = fun(
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("全息图"),
          Type.bitstring("xyz"),
        ]),
      );

      const expected = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
        Type.integer(20840),
        Type.integer(24687),
        Type.integer(22270),
        Type.integer(120),
        Type.integer(121),
        Type.integer(122),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("a list that contains some items that are not UTF8 binaries", () => {
      const data = Type.list([
        Type.bitstring("abc"),
        Type.integer(123),
        Type.bitstring("xyz"),
      ]);

      assert.throw(
        () => fun(data),
        HologramInterpreterError,
        "Function :unicode.characters_to_list/1 is not yet fully ported and at the moment accepts only UTF8 binary input.\n" +
          `The following input was received: ["abc", 123, "xyz"]\n` +
          "See what to do here: https://www.hologram.page/TODO",
      );
    });

    it("input other than a list or UTF8 binary", () => {
      assert.throw(
        () => fun(Type.integer(123)),
        HologramInterpreterError,
        "Function :unicode.characters_to_list/1 is not yet fully ported and at the moment accepts only UTF8 binary input.\n" +
          "The following input was received: 123\n" +
          "See what to do here: https://www.hologram.page/TODO",
      );
    });
  });

  describe("characters_to_nfc_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfc_binary/1"];

    it("normalizes combining characters to NFC", () => {
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

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

    it("returns error tuple on invalid UTF-8 in binary", () => {
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

    it("returns error tuple for truncated UTF-8 sequence", () => {
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
  });

  describe("characters_to_nfd_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfd_binary/1"];

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

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
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

    it("handles large input", () => {
      const largeInput = "abcdefghij".repeat(100);
      const input = Type.bitstring(largeInput);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring(largeInput));
    });

    it("handles mixed ASCII and Unicode", () => {
      const input = Type.list([
        Type.bitstring("hello"),
        Type.bitstring("  "),
        Type.bitstring("å"),
        Type.bitstring("  world"),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("hello  a\u030a  world"));
    });

    it("preserves non-combining characters", () => {
      const input = Type.list([
        Type.integer(0x3042), // Hiragana A
        Type.integer(0x3044), // Hiragana I
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("あい"));
    });

    it("returns error tuple on invalid UTF-8 in binary", () => {
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

    it("returns error tuple for truncated UTF-8 sequence", () => {
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

    it("raises ArgumentError on invalid code point", () => {
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
  });

  describe("characters_to_nfkc_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfkc_binary/1"];

    it("normalizes combining characters to NFKC", () => {
      const input = Type.bitstring("a\u030a");
      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("å"));
    });

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

    it("returns error tuple on invalid UTF-8 in binary", () => {
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

    it("returns error tuple for truncated UTF-8 sequence", () => {
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

    it("returns error tuple for single invalid binary not wrapped in a list", () => {
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
  });

  describe("characters_to_nfkd_binary/1", () => {
    const fun = Erlang_Unicode["characters_to_nfkd_binary/1"];

    it("normalizes combining characters to NFKD", () => {
      // Input: "a" + combining ring above (decomposed form)
      // NFKD: keeps it as decomposed
      const input = Type.bitstring("a\u030a");
      const result = fun(input);
      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("decomposes already normalized precomposed characters", () => {
      // Input: precomposed "å" (U+00E5)
      // NFKD: decomposes to "a" + combining ring above (U+0061 + U+030A)
      const input = Type.bitstring("å");
      const result = fun(input);
      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
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

      // Expected: "abc.." + "a\u030a" + "a\u0308" + "o\u0308"
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
      const input = Type.list([
        Type.list([Type.list([Type.bitstring("a"), Type.integer(0x030a)])]),
      ]);

      const result = fun(input);

      assert.deepStrictEqual(result, Type.bitstring("a\u030a"));
    });

    it("raises ArgumentError on invalid code point", () => {
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

    it("returns error tuple on invalid UTF-8 in binary", () => {
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

    it("handles multiple combining marks", () => {
      const input = Type.list([
        Type.bitstring("o"),
        Type.integer(0x0308), // Combining diaeresis
        Type.integer(0x0304), // Combining macron
      ]);

      const result = fun(input);

      // NFKD keeps combining marks as-is
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
        Type.bitstring("a"),
        Type.integer(0x030a),
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

    it("rejects overlong encoding (2-byte for ASCII)", () => {
      // Overlong encoding: 'A' (U+0041) encoded as 2 bytes: 0xC1 0x81
      const invalidBinary = Bitstring.fromBytes([0xc1, 0x81]);
      const input = Type.list([Type.bitstring("abc"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("abc"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects overlong encoding (3-byte for 2-byte range)", () => {
      // Overlong encoding: U+007F encoded as 3 bytes: 0xE0 0x81 0xBF
      const invalidBinary = Bitstring.fromBytes([0xe0, 0x81, 0xbf]);
      const input = Type.list([Type.bitstring("test"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("test"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate (high surrogate)", () => {
      // UTF-16 high surrogate: U+D800 encoded as 0xED 0xA0 0x80
      const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);
      const input = Type.list([Type.bitstring("hello"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("hello"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects UTF-16 surrogate (low surrogate)", () => {
      // UTF-16 low surrogate: U+DFFF encoded as 0xED 0xBF 0xBF
      const invalidBinary = Bitstring.fromBytes([0xed, 0xbf, 0xbf]);
      const input = Type.list([Type.bitstring("world"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("world"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects code point above U+10FFFF", () => {
      // U+110000 encoded as 4 bytes: 0xF4 0x90 0x80 0x80
      const invalidBinary = Bitstring.fromBytes([0xf4, 0x90, 0x80, 0x80]);
      const input = Type.list([Type.bitstring("xyz"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("xyz"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("rejects 4-byte overlong encoding", () => {
      // Overlong encoding: U+FFFF encoded as 4 bytes: 0xF0 0x8F 0xBF 0xBF
      const invalidBinary = Bitstring.fromBytes([0xf0, 0x8f, 0xbf, 0xbf]);
      const input = Type.list([Type.bitstring("pre"), invalidBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("pre"),
        invalidBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns error tuple for truncated UTF-8 sequence", () => {
      // Truncated UTF-8: start of a 2-byte sequence without continuation
      const truncatedBinary = Bitstring.fromBytes([0xc3]);
      const input = Type.list([Type.bitstring("test"), truncatedBinary]);

      const result = fun(input);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring("test"),
        truncatedBinary,
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });
});

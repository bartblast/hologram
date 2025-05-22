"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

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
      const input = Type.bitstring2("全息图");
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

      assert.deepStrictEqual(result, Type.bitstring2(""));
    });

    it("input is a list of ASCII code points", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.integer(98), // b
        Type.integer(99), // c
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring2("abc");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a list of non-ASCII code points (Chinese)", () => {
      const input = Type.list([
        Type.integer(20840), // 全
        Type.integer(24687), // 息
        Type.integer(22270), // 图
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring2("全息图");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a binary bitstring", () => {
      const input = Type.bitstring2("abc");

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      assert.deepStrictEqual(result, input);
    });

    it("input is a non-binary bitstring", () => {
      assertBoxedError(
        () =>
          characters_to_binary(Type.bitstring2([1, 0, 1]), utf8Atom, utf8Atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("input is a list of binary bitstrings", () => {
      const input = Type.list([
        Type.bitstring2("abc"),
        Type.bitstring2("def"),
        Type.bitstring2("ghi"),
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring2("abcdefghi");

      assert.deepStrictEqual(result, expected);
    });

    it("input is a list of non-binary bitstrings", () => {
      const input = Type.list([
        Type.bitstring2([1, 1, 0]),
        Type.bitstring2([1, 0, 1]),
        Type.bitstring2([0, 1, 1]),
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
        Type.bitstring2("bcd"),
        Type.integer(101), // e
        Type.bitstring2("fgh"),
        Type.integer(105), // i
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring2("abcdefghi");

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
            Type.bitstring2("def"),
            Type.integer(103), // g
          ]),
          Type.integer(104), // h
        ]),
        Type.integer(105), // i
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.bitstring2("abcdefghi");

      assert.deepStrictEqual(result, expected);
    });

    it("input contains invalid code points", () => {
      const input = Type.list([
        Type.integer(97), // a
        Type.bitstring2("bcd"),
        // Max Unicode code point value is 1,114,112
        Type.integer(1114113),
        Type.bitstring2("efg"),
      ]);

      const result = characters_to_binary(input, utf8Atom, utf8Atom);

      const expected = Type.tuple([
        Type.atom("error"),
        Type.bitstring2("abcd"),
        Type.list([Type.integer(1114113), Type.bitstring2("efg")]),
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
      const result = fun(Type.bitstring2("全息图"));

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
          Type.bitstring2("abc"),
          Type.bitstring2("全息图"),
          Type.bitstring2("xyz"),
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
        Type.bitstring2("abc"),
        Type.integer(123),
        Type.bitstring2("xyz"),
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
});

"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_UnicodeUtil from "../../../assets/js/erlang/unicode_util.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/unicode_util_test.exs
// Always update both together.

describe("Erlang_UnicodeUtil", () => {
  describe("cp/1", () => {
    const cp = Erlang_UnicodeUtil["cp/1"];

    describe("with binary input", () => {
      it("returns empty list for empty binary", () => {
        const input = Type.bitstring("");
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("extracts first codepoint from single character", () => {
        const input = Type.bitstring("a");
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.bitstring("")]),
        );
      });

      it("extracts first codepoint from multi-character string", () => {
        const input = Type.bitstring("hello");
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(104), Type.bitstring("ello")]),
        );
      });

      it("handles UTF-8 character (German ß)", () => {
        const input = Type.bitstring("ßtest");
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(223), Type.bitstring("test")]),
        );
      });

      it("handles emoji (outside BMP)", () => {
        const input = Type.bitstring("😀test");
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(128_512), Type.bitstring("test")]),
        );
      });

      it("returns error tuple for invalid UTF-8", () => {
        const input = Bitstring.fromBytes([255, 255]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.tuple([Type.atom("error"), input]));
      });

      it("returns error tuple for surrogate pair", () => {
        // Create invalid UTF-8 with surrogate pair codepoint
        const input = Bitstring.fromBytes([0xed, 0xa0, 0x80]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.tuple([Type.atom("error"), input]));
      });
    });

    describe("with list of integers", () => {
      it("returns empty list for empty list", () => {
        const input = Type.list();
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("extracts single integer", () => {
        const input = Type.list([Type.integer(97)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("extracts first integer from list", () => {
        const input = Type.list([
          Type.integer(104),
          Type.integer(101),
          Type.integer(108),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(104), Type.integer(101), Type.integer(108)]),
        );
      });

      it("handles zero codepoint", () => {
        const input = Type.list([Type.integer(0)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0)]));
      });

      it("handles maximum valid codepoint", () => {
        const input = Type.list([Type.integer(0x10ffff)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0x10ffff)]));
      });

      it("does not validate surrogate pair codepoint in list", () => {
        // Erlang does not validate surrogate pairs in integer lists
        const input = Type.list([Type.integer(55296)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(55296)]));
      });

      it("raises FunctionClauseError for negative integer", () => {
        const input = Type.list([Type.integer(-1)]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(-1),
          ]),
        );
      });

      it("raises FunctionClauseError for integer above maximum", () => {
        const input = Type.list([Type.integer(0x110000)]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(0x110000),
          ]),
        );
      });
    });

    describe("with list starting with binary", () => {
      it("extracts codepoint from single character binary", () => {
        const input = Type.list([Type.bitstring("a"), Type.integer(98)]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), Type.bitstring(""), Type.integer(98)]),
        );
      });

      it("extracts codepoint from multi-character binary", () => {
        const input = Type.list([Type.bitstring("hello"), Type.integer(97)]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(104),
            Type.bitstring("ello"),
            Type.integer(97),
          ]),
        );
      });

      it("handles binary alone in list", () => {
        const input = Type.list([Type.bitstring("test")]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(116), Type.bitstring("est")]),
        );
      });

      it("skips empty binary and processes next element", () => {
        const input = Type.list([Type.bitstring(""), Type.integer(97)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles multiple empty binaries", () => {
        const input = Type.list([
          Type.bitstring(""),
          Type.bitstring(""),
          Type.integer(97),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("returns error tuple for invalid UTF-8 in binary", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.list([invalidBinary]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
      });

      it("raises FunctionClauseError for non-byte-aligned bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);
        const input = Type.list([bitstring]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });
    });

    describe("with nested list", () => {
      it("extracts from single nested integer", () => {
        const input = Type.list([Type.list([Type.integer(97)])]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("extracts from nested list with multiple integers", () => {
        const input = Type.list([
          Type.list([Type.integer(104), Type.integer(101)]),
          Type.integer(108),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(104), Type.integer(101), Type.integer(108)]),
        );
      });

      it("extracts from nested list with binary", () => {
        const input = Type.list([
          Type.list([Type.bitstring("ab")]),
          Type.integer(99),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(99)]),
        );
      });

      it("skips empty nested list", () => {
        const input = Type.list([Type.list(), Type.integer(97)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles deeply nested list", () => {
        const input = Type.list([Type.list([Type.list([Type.integer(97)])])]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("returns empty list for nested empty lists", () => {
        const input = Type.list([Type.list(), Type.list()]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });
    });

    describe("error handling", () => {
      it("raises FunctionClauseError for integer input", () => {
        const input = Type.integer(42);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for atom input", () => {
        const input = Type.atom("test");

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for float input", () => {
        const input = Type.float(3.14);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for non-byte-aligned bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () => cp(bitstring),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });

      it("raises FunctionClauseError for list with atom", () => {
        const input = Type.list([Type.atom("invalid")]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.atom("invalid"),
          ]),
        );
      });

      it("raises FunctionClauseError for list with float", () => {
        const input = Type.list([Type.float(3.14)]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.float(3.14),
          ]),
        );
      });
    });
  });
});

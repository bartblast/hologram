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

    describe("with improper lists", () => {
      it("handles improper list with integer tail", () => {
        const input = Type.improperList([Type.integer(97), Type.integer(98)]);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("handles improper list with binary tail", () => {
        const input = Type.improperList([
          Type.integer(97),
          Type.bitstring("bc"),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("handles improper list with binary head and tail", () => {
        const input = Type.improperList([
          Type.bitstring("ab"),
          Type.bitstring("cd"),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([
            Type.integer(97),
            Type.bitstring("b"),
            Type.bitstring("cd"),
          ]),
        );
      });

      it("handles improper list with binary and empty list tail", () => {
        const input = Type.improperList([Type.bitstring("ab"), Type.list()]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.bitstring("b")]),
        );
      });

      it("handles improper list with empty binary and empty list tail", () => {
        const input = Type.improperList([Type.bitstring(""), Type.list()]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("handles improper list with empty lists", () => {
        const input = Type.improperList([Type.list(), Type.list()]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("passes through improper list with atom tail", () => {
        const input = Type.improperList([Type.integer(97), Type.atom("atom")]);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("passes through improper list with float tail", () => {
        const input = Type.improperList([Type.integer(97), Type.float(3.14)]);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("passes through improper list with non-byte-aligned bitstring tail", () => {
        const bitstring = Type.bitstring([1, 0, 1]);
        const input = Type.improperList([Type.integer(97), bitstring]);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("passes through improper list with invalid UTF-8 binary tail", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.improperList([Type.integer(97), invalidBinary]);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
      });

      it("handles nested improper list with integers", () => {
        const input = Type.list([
          Type.improperList([Type.integer(97), Type.integer(98)]),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.integer(98)]),
        );
      });

      it("passes through nested improper list with atom tail", () => {
        const input = Type.list([
          Type.improperList([Type.integer(97), Type.atom("atom")]),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.atom("atom")]),
        );
      });

      it("handles nested improper list with binary and empty list tail", () => {
        const input = Type.list([
          Type.improperList([Type.bitstring("ab"), Type.list()]),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.bitstring("b")]),
        );
      });

      it("handles improper list with nested valid codepoint and binary tail", () => {
        const input = Type.improperList([
          Type.list([Type.integer(97), Type.integer(98)]),
          Type.bitstring("cd"),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([
            Type.integer(97),
            Type.integer(98),
            Type.bitstring("cd"),
          ]),
        );
      });

      it("raises FunctionClauseError for nested improper list with empty list and integer tail", () => {
        const input = Type.list([
          Type.improperList([Type.list(), Type.integer(97)]),
        ]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(97),
          ]),
        );
      });

      it("raises FunctionClauseError for nested improper list with empty binary and integer tail", () => {
        const input = Type.list([
          Type.improperList([Type.bitstring(""), Type.integer(97)]),
        ]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(97),
          ]),
        );
      });
    });

    describe("with mixed content", () => {
      it("handles multiple binaries in list", () => {
        const input = Type.list([
          Type.bitstring("ab"),
          Type.bitstring("cd"),
          Type.integer(97),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(97),
            Type.bitstring("b"),
            Type.bitstring("cd"),
            Type.integer(97),
          ]),
        );
      });

      it("handles consecutive non-empty binaries in list", () => {
        const input = Type.list([
          Type.bitstring("ab"),
          Type.bitstring("cd"),
          Type.bitstring("ef"),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(97),
            Type.bitstring("b"),
            Type.bitstring("cd"),
            Type.bitstring("ef"),
          ]),
        );
      });

      it("handles list with alternating integers and binaries", () => {
        const input = Type.list([
          Type.integer(97),
          Type.bitstring("b"),
          Type.integer(99),
          Type.bitstring("d"),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(97),
            Type.bitstring("b"),
            Type.integer(99),
            Type.bitstring("d"),
          ]),
        );
      });

      it("does not error on invalid UTF-8 after valid integer", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.list([Type.integer(97), invalidBinary]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), invalidBinary]),
        );
      });

      // Tests O(n) optimization: avoids O(n²) slicing behavior when processing long lists
      it("handles very long list of integers", () => {
        const longList = Array.from({length: 100}, (_elem, index) =>
          Type.integer(index + 1),
        );

        const input = Type.list(longList);
        const result = cp(input);

        assert.deepStrictEqual(result, input);
        assert.strictEqual(result.data.length, 100);
      });

      it("handles nested then flat integers", () => {
        const input = Type.list([
          Type.list([Type.integer(97), Type.integer(98)]),
          Type.integer(99),
          Type.integer(100),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(97),
            Type.integer(98),
            Type.integer(99),
            Type.integer(100),
          ]),
        );
      });

      it("handles very deeply nested lists", () => {
        const input = Type.list([
          Type.list([Type.list([Type.list([Type.integer(97)])])]),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles multiple nested empty binaries with following integer", () => {
        const input = Type.list([
          Type.list([Type.bitstring("")]),
          Type.list([Type.bitstring("")]),
          Type.integer(97),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles nested empty binary and empty list with following integer", () => {
        const input = Type.list([
          Type.list([Type.bitstring(""), Type.list()]),
          Type.integer(97),
        ]);

        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles empty nested list followed by valid nested list", () => {
        const input = Type.list([Type.list(), Type.list([Type.integer(97)])]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(97)]));
      });

      it("handles list with only empty nested lists", () => {
        const input = Type.list([Type.list(), Type.list(), Type.list()]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list());
      });
    });

    describe("UTF-8 and encoding edge cases", () => {
      it("handles codepoint at 0 (null character)", () => {
        const input = Type.list([Type.integer(0)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0)]));
      });

      it("handles binary containing null character", () => {
        const input = Bitstring.fromBytes([0, 97, 98]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(0), Type.bitstring("ab")]),
        );
      });

      it("handles BMP boundary - maximum BMP codepoint", () => {
        const input = Type.list([Type.integer(0xffff)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0xffff)]));
      });

      it("handles first codepoint above BMP", () => {
        const input = Type.list([Type.integer(0x10000)]);
        const result = cp(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0x10000)]));
      });

      it("handles UTF-8 two-byte character (¢)", () => {
        const input = Bitstring.fromBytes([0xc2, 0xa2, 99]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(162), Type.bitstring("c")]),
        );
      });

      it("handles UTF-8 three-byte character (€)", () => {
        const input = Bitstring.fromBytes([0xe2, 0x82, 0xac]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(8364), Type.bitstring("")]),
        );
      });

      it("returns error tuple for overlong UTF-8 encoding", () => {
        const invalidBinary = Bitstring.fromBytes([0xc0, 0x80]);
        const result = cp(invalidBinary);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
      });

      it("returns error tuple for lone continuation byte", () => {
        const invalidBinary = Bitstring.fromBytes([0x80]);
        const result = cp(invalidBinary);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
      });

      it("returns error tuple for invalid 5-byte UTF-8 sequence", () => {
        const invalidBinary = Bitstring.fromBytes([
          0xf8, 0x80, 0x80, 0x80, 0x80,
        ]);

        const result = cp(invalidBinary);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
      });

      it("returns error tuple for truncated UTF-8 sequence", () => {
        const invalidBinary = Bitstring.fromBytes([0xc3]);
        const result = cp(invalidBinary);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
      });

      it("returns error tuple for nested invalid UTF-8", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.list([Type.list([invalidBinary])]);
        const result = cp(input);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalidBinary]),
        );
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

      it("raises FunctionClauseError for non-byte-aligned bitstring (direct)", () => {
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

      it("raises FunctionClauseError for list with atom head and tail", () => {
        const input = Type.list([Type.atom("a"), Type.atom("b")]);

        assertBoxedError(
          () => cp(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl/2", [
            Type.atom("a"),
            Type.list([Type.atom("b")]),
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

  describe("gc/1", () => {
    const gc = Erlang_UnicodeUtil["gc/1"];

    describe("with binary input", () => {
      it("returns empty list for empty binary", () => {
        const result = gc(Type.bitstring(""));

        assert.deepStrictEqual(result, Type.list());
      });

      it("extracts first grapheme from ascii string", () => {
        const result = gc(Type.bitstring("ab"));

        assert.deepStrictEqual(
          result,
          Type.improperList([Type.integer(97), Type.bitstring("b")]),
        );
      });

      it("handles grapheme with combining mark", () => {
        const result = gc(Type.bitstring("e̊x"));

        assert.deepStrictEqual(
          result,
          Type.improperList([
            Type.list([Type.integer(101), Type.integer(778)]),
            Type.bitstring("x"),
          ]),
        );
      });

      it("returns error tuple for invalid UTF-8", () => {
        const invalid = Bitstring.fromBytes([255, 255]);
        const result = gc(invalid);

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("error"), invalid]),
        );
      });
    });

    describe("with list input", () => {
      it("returns empty list for empty list", () => {
        const result = gc(Type.list());

        assert.deepStrictEqual(result, Type.list());
      });

      it("handles list of integers", () => {
        const result = gc(Type.list([Type.integer(97), Type.integer(98)]));

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), Type.integer(98)]),
        );
      });

      it("groups combining marks across integers", () => {
        const result = gc(
          Type.list([Type.integer(97), Type.integer(778), Type.integer(120)]),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(97), Type.integer(778)]),
            Type.integer(120),
          ]),
        );
      });

      it("handles list starting with binary", () => {
        const result = gc(Type.list([Type.bitstring("ab"), Type.integer(98)]));

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(98)]),
        );
      });

      it("handles binary with combining marks inside list", () => {
        const result = gc(Type.list([Type.bitstring("e̊"), Type.integer(120)]));

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(101), Type.integer(778)]),
            Type.bitstring(""),
            Type.integer(120),
          ]),
        );
      });

      it("handles integer followed by empty binary", () => {
        const result = gc(Type.list([Type.integer(97), Type.bitstring("")]));

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(97), Type.bitstring("")]),
        );
      });
    });

    describe("error handling", () => {
      it("raises FunctionClauseError for non-byte-aligned bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () => gc(bitstring),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });

      it("raises FunctionClauseError for integer input", () => {
        const input = Type.integer(42);

        assertBoxedError(
          () => gc(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            input,
          ]),
        );
      });
    });
  });
});

"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Elixir_Utils from "../../../assets/js/erlang/elixir_utils.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/elixir_utils_test.exs
// Always update both together.

describe("Erlang_Elixir_Utils", () => {
  describe("jaro_similarity/2", () => {
    const jaroSimilarity = Erlang_Elixir_Utils["jaro_similarity/2"];

    it("returns 1.0 for identical strings", () => {
      const result = jaroSimilarity(
        Type.bitstring("hello"),
        Type.bitstring("hello"),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("returns 1.0 when both inputs are empty", () => {
      const result = jaroSimilarity(Type.bitstring(""), Type.bitstring(""));

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("returns 0.0 for completely different inputs", () => {
      const result = jaroSimilarity(
        Type.bitstring("abc"),
        Type.bitstring("xyz"),
      );

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns 0.0 when first input is empty", () => {
      const result = jaroSimilarity(
        Type.bitstring(""),
        Type.bitstring("hello"),
      );

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns 0.0 when second input is empty", () => {
      const result = jaroSimilarity(
        Type.bitstring("hello"),
        Type.bitstring(""),
      );

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns 0.0 for identical single characters", () => {
      // Known issue in :elixir_utils.jaro_similarity/2.
      // Elixir will eventually switch to :string.jaro_similarity/2
      // when it requires Erlang/OTP 27+.
      const result = jaroSimilarity(Type.bitstring("a"), Type.bitstring("a"));

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns 0.0 for different single characters", () => {
      const result = jaroSimilarity(Type.bitstring("a"), Type.bitstring("b"));

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns 0.0 for completely transposed two-character string", () => {
      const result = jaroSimilarity(Type.bitstring("ab"), Type.bitstring("ba"));

      assertBoxedStrictEqual(result, Type.float(0.0));
    });

    it("returns similarity score with partial transposition", () => {
      const result = jaroSimilarity(
        Type.bitstring("abcd"),
        Type.bitstring("abdc"),
      );

      assertBoxedStrictEqual(result, Type.float(0.9166666666666666));
    });

    it("handles slight deviations", () => {
      const result1 = jaroSimilarity(
        Type.bitstring("martha"),
        Type.bitstring("marhta"),
      );

      assertBoxedStrictEqual(result1, Type.float(0.9444444444444445));

      const result2 = jaroSimilarity(
        Type.bitstring("dwayne"),
        Type.bitstring("duane"),
      );

      assertBoxedStrictEqual(result2, Type.float(0.8222222222222223));

      const result3 = jaroSimilarity(
        Type.bitstring("dixon"),
        Type.bitstring("dicksonx"),
      );

      assertBoxedStrictEqual(result3, Type.float(0.7666666666666666));
    });

    it("is case sensitive", () => {
      const result = jaroSimilarity(
        Type.bitstring("Hello"),
        Type.bitstring("hello"),
      );

      assertBoxedStrictEqual(result, Type.float(0.8666666666666667));
    });

    it("handles Unicode characters", () => {
      const result = jaroSimilarity(
        Type.bitstring("café"),
        Type.bitstring("cafe"),
      );

      assertBoxedStrictEqual(result, Type.float(0.8333333333333334));
    });

    it("handles emoji characters", () => {
      const result = jaroSimilarity(
        Type.bitstring("hello😀"),
        Type.bitstring("hello😀"),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("works with strings, charlists, and integer lists producing same results", () => {
      const strResult = jaroSimilarity(
        Type.bitstring("abc"),
        Type.bitstring("abd"),
      );

      const charResult = jaroSimilarity(
        Type.charlist("abc"),
        Type.charlist("abd"),
      );

      const intResult = jaroSimilarity(
        Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
        Type.list([Type.integer(97), Type.integer(98), Type.integer(100)]),
      );

      assert.deepStrictEqual(strResult, charResult);
      assert.deepStrictEqual(charResult, intResult);
    });

    it("handles lists with string elements", () => {
      const result = jaroSimilarity(
        Type.list([
          Type.bitstring("a"),
          Type.bitstring("b"),
          Type.bitstring("c"),
        ]),
        Type.list([
          Type.bitstring("a"),
          Type.bitstring("b"),
          Type.bitstring("c"),
        ]),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("handles lists with mixed integers and strings", () => {
      const result = jaroSimilarity(
        Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(99)]),
        Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(99)]),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("handles lists with multi-character strings", () => {
      const result = jaroSimilarity(
        Type.list([Type.bitstring("ab"), Type.bitstring("cd")]),
        Type.list([Type.bitstring("ab"), Type.bitstring("cd")]),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    it("handles nested lists", () => {
      const result = jaroSimilarity(
        Type.list([
          Type.integer(97),
          Type.integer(98),
          Type.list([Type.integer(99)]),
        ]),
        Type.list([
          Type.integer(97),
          Type.integer(98),
          Type.list([Type.integer(99)]),
        ]),
      );

      assertBoxedStrictEqual(result, Type.float(1.0));
    });

    // Error case tests
    // - Top-level invalid argument raises :unicode_util.cp/1 error
    // - Single-element list with invalid type raises :unicode_util.cp/1 error
    // - Multi-element list with invalid type raises :unicode_util.cpl/2 error (with remaining elements)

    it("raises FunctionClauseError when first argument is not bitstring or list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [Type.integer(123)],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.integer(123), Type.bitstring("hello")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when second argument is not bitstring or list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [Type.integer(123)],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.bitstring("hello"), Type.integer(123)),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when first argument is non-binary bitstring", () => {
      const arg = Type.bitstring([1, 0, 1]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [arg],
      );

      assertBoxedError(
        () => jaroSimilarity(arg, Type.bitstring("hello")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when second argument is non-binary bitstring", () => {
      const arg = Type.bitstring([1, 0, 1]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [arg],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.bitstring("hello"), arg),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when first argument is single-element list with invalid element", () => {
      const emptyMap = Type.map();

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [emptyMap],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.list([emptyMap]), Type.bitstring("hello")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when second argument is single-element list with invalid element", () => {
      const emptyMap = Type.map();

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [emptyMap],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.bitstring("hello"), Type.list([emptyMap])),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when first argument is multi-element list with invalid element", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cpl/2",
        [Type.atom("a"), Type.list([Type.atom("b")])],
      );

      assertBoxedError(
        () =>
          jaroSimilarity(
            Type.list([Type.atom("a"), Type.atom("b")]),
            Type.bitstring("hello"),
          ),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when second argument is multi-element list with invalid element", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cpl/2",
        [Type.atom("a"), Type.list([Type.atom("b")])],
      );

      assertBoxedError(
        () =>
          jaroSimilarity(
            Type.bitstring("hello"),
            Type.list([Type.atom("a"), Type.atom("b")]),
          ),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ArgumentError for invalid UTF-8 bytes", () => {
      const invalidUtf8 = Bitstring.fromBytes([255, 254, 253]);
      const expectedMessage = "argument error: <<255, 254, 253>>";

      assertBoxedError(
        () => jaroSimilarity(invalidUtf8, Type.bitstring("test")),
        "ArgumentError",
        expectedMessage,
      );
    });
  });
});

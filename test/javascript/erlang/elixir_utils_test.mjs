"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

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
      assert.strictEqual(result.value, 1.0);
    });

    it("returns 1.0 when both inputs are empty", () => {
      const result = jaroSimilarity(Type.bitstring(""), Type.bitstring(""));
      assert.strictEqual(result.value, 1.0);
    });

    it("returns 0.0 for completely different inputs", () => {
      const result = jaroSimilarity(
        Type.bitstring("abc"),
        Type.bitstring("xyz"),
      );
      assert.strictEqual(result.value, 0.0);
    });

    it("returns 0.0 when first input is empty", () => {
      const result = jaroSimilarity(
        Type.bitstring(""),
        Type.bitstring("hello"),
      );
      assert.strictEqual(result.value, 0.0);
    });

    it("returns 0.0 when second input is empty", () => {
      const result = jaroSimilarity(
        Type.bitstring("hello"),
        Type.bitstring(""),
      );
      assert.strictEqual(result.value, 0.0);
    });

    it("returns 0.0 for identical single characters", () => {
      // Known issue in :elixir_utils.jaro_similarity/2
      // will be fixed when Elixir requires Erlang/OTP 27+
      // and switches to :string.jaro_similarity/2
      const result = jaroSimilarity(Type.bitstring("a"), Type.bitstring("a"));
      assert.strictEqual(result.value, 0.0);
    });

    it("returns 0.0 for different single characters", () => {
      const result = jaroSimilarity(Type.bitstring("a"), Type.bitstring("b"));
      assert.strictEqual(result.value, 0.0);
    });

    it("returns 0.0 for completely transposed two-character string", () => {
      const result = jaroSimilarity(Type.bitstring("ab"), Type.bitstring("ba"));
      assert.strictEqual(result.value, 0.0);
    });

    it("returns similarity score with partial transposition", () => {
      const result = jaroSimilarity(
        Type.bitstring("abcd"),
        Type.bitstring("abdc"),
      );
      assert.strictEqual(result.value, 0.9166666666666666);
    });

    it("handles slight deviations", () => {
      const result1 = jaroSimilarity(
        Type.bitstring("martha"),
        Type.bitstring("marhta"),
      );
      assert.strictEqual(result1.value, 0.9444444444444445);

      const result2 = jaroSimilarity(
        Type.bitstring("dwayne"),
        Type.bitstring("duane"),
      );
      assert.strictEqual(result2.value, 0.8222222222222223);

      const result3 = jaroSimilarity(
        Type.bitstring("dixon"),
        Type.bitstring("dicksonx"),
      );
      assert.strictEqual(result3.value, 0.7666666666666666);
    });

    it("is case sensitive", () => {
      const result = jaroSimilarity(
        Type.bitstring("Hello"),
        Type.bitstring("hello"),
      );
      assert.strictEqual(result.value, 0.8666666666666667);
    });

    it("handles unicode characters", () => {
      const result = jaroSimilarity(
        Type.bitstring("café"),
        Type.bitstring("cafe"),
      );
      assert.strictEqual(result.value, 0.8333333333333334);
    });

    it("handles emoji characters", () => {
      const result = jaroSimilarity(
        Type.bitstring("hello😀"),
        Type.bitstring("hello😀"),
      );
      assert.strictEqual(result.value, 1.0);
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
      assert.strictEqual(result.value, 1.0);
    });

    it("handles lists with mixed integers and strings", () => {
      const result = jaroSimilarity(
        Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(99)]),
        Type.list([Type.integer(97), Type.bitstring("b"), Type.integer(99)]),
      );
      assert.strictEqual(result.value, 1.0);
    });

    it("handles lists with multi-character strings", () => {
      const result = jaroSimilarity(
        Type.list([Type.bitstring("ab"), Type.bitstring("cd")]),
        Type.list([Type.bitstring("ab"), Type.bitstring("cd")]),
      );
      assert.strictEqual(result.value, 1.0);
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
      assert.strictEqual(result.value, 1.0);
    });

    // Error handling tests
    // - Top-level invalid argument raises :unicode_util.cp/1 error
    // - Single-element list with invalid type raises :unicode_util.cp/1 error
    // - Multi-element list with invalid type raises :unicode_util.cpl/2 error (with remaining elements)

    it("raises FunctionClauseError for invalid arguments", () => {
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

    it("raises FunctionClauseError for single-element list with invalid type", () => {
      const emptyMap = Type.map([]);
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cp/1",
        [emptyMap],
      );

      assertBoxedError(
        () => jaroSimilarity(Type.list([emptyMap]), Type.list([emptyMap])),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError for multi-element list with invalid type", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":unicode_util.cpl/2",
        [Type.atom("a"), Type.list([Type.atom("b")])],
      );

      assertBoxedError(
        () =>
          jaroSimilarity(
            Type.list([Type.atom("a"), Type.atom("b")]),
            Type.list([Type.atom("a"), Type.atom("b")]),
          ),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ArgumentError for invalid UTF-8 bytes", () => {
      const invalidUtf8 = Type.bitstring("");
      invalidUtf8.bytes = new Uint8Array([255, 254, 253]);
      invalidUtf8.text = null;

      const expectedMessage = `argument error: ${Interpreter.inspect(invalidUtf8)}`;

      assertBoxedError(
        () => jaroSimilarity(invalidUtf8, Type.bitstring("test")),
        "ArgumentError",
        expectedMessage,
      );
    });
  });
});

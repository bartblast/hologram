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

    it("handles slight deviations", () => {
      const result1 = jaroSimilarity(
        Type.bitstring("martha"),
        Type.bitstring("marhta"),
      );
      assert.ok(Math.abs(result1.value - 0.944) < 0.001);

      const result2 = jaroSimilarity(
        Type.bitstring("dwayne"),
        Type.bitstring("duane"),
      );
      assert.ok(Math.abs(result2.value - 0.822) < 0.001);

      const result3 = jaroSimilarity(
        Type.bitstring("dixon"),
        Type.bitstring("dicksonx"),
      );
      assert.ok(Math.abs(result3.value - 0.767) < 0.001);
    });

    it("returns 0.0 for completely different inputs", () => {
      const result = jaroSimilarity(
        Type.bitstring("abc"),
        Type.bitstring("xyz"),
      );
      assert.strictEqual(result.value, 0.0);
    });

    it("handles empty inputs", () => {
      const result1 = jaroSimilarity(Type.bitstring(""), Type.bitstring(""));
      assert.strictEqual(result1.value, 1.0);

      const result2 = jaroSimilarity(
        Type.bitstring(""),
        Type.bitstring("hello"),
      );
      assert.strictEqual(result2.value, 0.0);

      const result3 = jaroSimilarity(
        Type.bitstring("hello"),
        Type.bitstring(""),
      );
      assert.strictEqual(result3.value, 0.0);
    });

    it("handles single character inputs", () => {
      // Known issue in :elixir_utils.jaro_similarity/2
      // will be fixed when Elixir requires Erlang/OTP 27+
      // and switches to :string.jaro_similarity/2
      const result1 = jaroSimilarity(Type.bitstring("a"), Type.bitstring("a"));
      assert.strictEqual(result1.value, 0.0);

      const result2 = jaroSimilarity(Type.bitstring("a"), Type.bitstring("b"));
      assert.strictEqual(result2.value, 0.0);
    });

    it("handles transpositions", () => {
      const result1 = jaroSimilarity(
        Type.bitstring("ab"),
        Type.bitstring("ba"),
      );
      assert.strictEqual(result1.value, 0.0);

      const result2 = jaroSimilarity(
        Type.bitstring("abcd"),
        Type.bitstring("abdc"),
      );
      assert.ok(result2.value > 0.9);
    });

    it("is case sensitive", () => {
      const result = jaroSimilarity(
        Type.bitstring("Hello"),
        Type.bitstring("hello"),
      );
      assert.ok(result.value < 1.0);
    });

    it("handles unicode characters", () => {
      const result = jaroSimilarity(
        Type.bitstring("café"),
        Type.bitstring("cafe"),
      );
      assert.ok(result.value < 1.0);
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
          Type.integer(1),
          Type.integer(2),
          Type.list([Type.integer(1)]),
        ]),
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.list([Type.integer(1)]),
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
  });
});

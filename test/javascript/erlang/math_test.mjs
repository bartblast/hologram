"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Math from "../../../assets/js/erlang/math.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/math_test.exs
// Always update both together.

describe("Erlang_Math", () => {
  describe("ceil/1", () => {
    const testedFun = Erlang_Math["ceil/1"];

    it("rounds positive float with fractional part up", () => {
      const result = testedFun(Type.float(1.23));

      assert.deepStrictEqual(result, Type.float(2.0));
    });

    it("rounds negative float with fractional part up toward zero", () => {
      const result = testedFun(Type.float(-1.23));

      assert.deepStrictEqual(result, Type.float(-1.0));
    });

    it("keeps positive float without fractional part unchanged", () => {
      const result = testedFun(Type.float(1.0));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("keeps negative float without fractional part unchanged", () => {
      const result = testedFun(Type.float(-1.0));

      assert.deepStrictEqual(result, Type.float(-1.0));
    });

    it("keeps signed negative zero float unchanged", () => {
      const result = testedFun(Type.float(-0.0));

      assert.deepStrictEqual(result, Type.float(-0.0));
    });

    it("keeps signed positive zero float unchanged", () => {
      const result = testedFun(Type.float(+0.0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("keeps unsigned zero float unchanged", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("keeps positive integer unchanged", () => {
      const result = testedFun(Type.integer(1));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("keeps negative integer unchanged", () => {
      const result = testedFun(Type.integer(-1));

      assert.deepStrictEqual(result, Type.float(-1.0));
    });

    it("keeps zero integer unchanged", () => {
      const result = testedFun(Type.integer(0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number")
      );
    });
  });

  describe("log/1", () => {
    const testedFun = Erlang_Math["log/1"];

    it("returns natural logarithm of positive integer one", () => {
      const result = testedFun(Type.integer(1));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("returns natural logarithm of positive float one", () => {
      const result = testedFun(Type.float(1.0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("returns natural logarithm of e (approximately 1.0)", () => {
      const result = testedFun(Type.float(2.718281828459045));

      assert.ok(Math.abs(result.value - 1.0) < 0.0000001);
    });

    it("returns natural logarithm of positive integer", () => {
      const result = testedFun(Type.integer(10));

      assert.ok(result.value > 2.0 && result.value < 2.5);
    });

    it("returns natural logarithm of positive float", () => {
      const result = testedFun(Type.float(10.5));

      assert.ok(result.value > 2.3 && result.value < 2.4);
    });

    it("returns natural logarithm of large positive integer", () => {
      const result = testedFun(Type.integer(100));

      assert.ok(result.value > 4.6 && result.value < 4.7);
    });

    it("returns natural logarithm of large positive float", () => {
      const result = testedFun(Type.float(100.0));

      assert.ok(result.value > 4.6 && result.value < 4.7);
    });

    it("returns natural logarithm of small positive float", () => {
      const result = testedFun(Type.float(0.5));

      assert.ok(result.value < 0 && result.value > -1);
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number")
      );
    });

    it("raises ArithmeticError for zero integer", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0)),
        "ArithmeticError",
        "bad argument in arithmetic expression"
      );
    });

    it("raises ArithmeticError for zero float", () => {
      assertBoxedError(
        () => testedFun(Type.float(0.0)),
        "ArithmeticError",
        "bad argument in arithmetic expression"
      );
    });

    it("raises ArithmeticError for negative integer", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-1)),
        "ArithmeticError",
        "bad argument in arithmetic expression"
      );
    });

    it("raises ArithmeticError for negative float", () => {
      assertBoxedError(
        () => testedFun(Type.float(-1.0)),
        "ArithmeticError",
        "bad argument in arithmetic expression"
      );
    });
  });

  describe("pow/2", () => {
    const testedFun = Erlang_Math["pow/2"];

    it("returns base integer value raised to exponent integer value", () => {
      const result = testedFun(Type.integer(7), Type.integer(3));

      assert.deepStrictEqual(result, Type.float(343.0));
    });

    it("returns base integer value raised to exponent float value", () => {
      const result = testedFun(Type.integer(4), Type.float(0.5));

      assert.deepStrictEqual(result, Type.float(2.0));
    });

    it("returns base float value raised to exponent integer value", () => {
      const result = testedFun(Type.float(2.5), Type.integer(2));

      assert.deepStrictEqual(result, Type.float(6.25));
    });

    it("returns base float value raised to exponent float value", () => {
      const result = testedFun(Type.float(9.0), Type.float(0.5));

      assert.deepStrictEqual(result, Type.float(3.0));
    });

    it("returns negative base integer value raised to integer exponent", () => {
      const result = testedFun(Type.integer(-2), Type.integer(3));

      assert.deepStrictEqual(result, Type.float(-8.0));
    });

    it("returns negative base integer value raised to float exponent with no fractional part", () => {
      const result = testedFun(Type.integer(-2), Type.float(3.0));

      assert.deepStrictEqual(result, Type.float(-8.0));
    });

    it("returns negative base float value raised to integer exponent", () => {
      const result = testedFun(Type.float(-2.5), Type.integer(2));

      assert.deepStrictEqual(result, Type.float(6.25));
    });

    it("returns base value raised to zero exponent", () => {
      const result = testedFun(Type.integer(7), Type.integer(0));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("returns zero base raised to zero exponent", () => {
      const result = testedFun(Type.integer(0), Type.integer(0));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("returns zero base raised to positive exponent", () => {
      const result = testedFun(Type.integer(0), Type.integer(5));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("returns base value raised to negative integer exponent", () => {
      const result = testedFun(Type.integer(2), Type.integer(-3));

      assert.deepStrictEqual(result, Type.float(0.125));
    });

    it("returns base value raised to negative float exponent", () => {
      const result = testedFun(Type.integer(4), Type.float(-0.5));

      assert.deepStrictEqual(result, Type.float(0.5));
    });

    it("raises ArgumentError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(3)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number")
      );
    });

    it("raises ArgumentError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.integer(7), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a number")
      );
    });

    it("raises ArithmeticError if the base is less than zero and exponent has a fractional part", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-7), Type.float(0.5)),
        "ArithmeticError",
        "bad argument in arithmetic expression"
      );
    });
  });
});

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

      assert.deepStrictEqual(result, Type.float(+0.0));
    });

    it("keeps unsigned zero float unchanged", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("converts positive integer to float", () => {
      const result = testedFun(Type.integer(1));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("converts negative integer to float", () => {
      const result = testedFun(Type.integer(-1));

      assert.deepStrictEqual(result, Type.float(-1.0));
    });

    it("converts zero integer to float", () => {
      const result = testedFun(Type.integer(0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("exp/1", () => {
    const exp = Erlang_Math["exp/1"];

    it("returns correct value if passing a positive float value", () => {
      const number = Type.float(2);

      const result = exp(number);
      const expected = Type.float(7.38905609893065);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing a negative float value", () => {
      const number = Type.float(-2);

      const result = exp(number);
      const expected = Type.float(0.1353352832366127);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing one as a float", () => {
      const number = Type.float(1.0);

      const result = exp(number);
      const expected = Type.float(2.718281828459045);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing zero as a float", () => {
      const number = Type.float(0);

      const result = exp(number);
      const expected = Type.float(1.0);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing a positive integer", () => {
      const number = Type.integer(2);

      const result = exp(number);
      const expected = Type.float(7.38905609893065);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing negative integer", () => {
      const number = Type.integer(-2);

      const result = exp(number);
      const expected = Type.float(0.1353352832366127);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing one as an integer", () => {
      const number = Type.integer(1);

      const result = exp(number);
      const expected = Type.float(2.718281828459045);

      assert.deepStrictEqual(result, expected);
    });

    it("returns correct value if passing zero as an integer", () => {
      const number = Type.integer(0);

      const result = exp(number);
      const expected = Type.float(1.0);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the argument is not a number", () => {
      const integerString = Type.string("12345");

      assertBoxedError(
        () => exp(integerString),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("floor/1", () => {
    const testedFun = Erlang_Math["floor/1"];

    it("rounds positive float with fractional part down", () => {
      const result = testedFun(Type.float(1.23));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("rounds negative float with fractional part down", () => {
      const result = testedFun(Type.float(-1.23));

      assert.deepStrictEqual(result, Type.float(-2.0));
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

      assert.deepStrictEqual(result, Type.float(+0.0));
    });

    it("keeps unsigned zero float unchanged", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("converts positive integer to float", () => {
      const result = testedFun(Type.integer(1));

      assert.deepStrictEqual(result, Type.float(1.0));
    });

    it("converts negative integer to float", () => {
      const result = testedFun(Type.integer(-1));

      assert.deepStrictEqual(result, Type.float(-1.0));
    });

    it("converts zero integer to float", () => {
      const result = testedFun(Type.integer(0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
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
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });

    it("raises ArgumentError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.integer(7), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a number"),
      );
    });

    it("raises ArithmeticError if the base is less than zero and exponent has a fractional part", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-7), Type.float(0.5)),
        "ArithmeticError",
        "bad argument in arithmetic expression",
      );
    });
  });
});

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
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("pow/2", () => {
    const testedFun = Erlang_Math["pow/2"];

    it("returns base value raised to exponent integer value", () => {
      const result = testedFun(Type.integer(7), Type.integer(3));

      assert.deepStrictEqual(result, Type.float(343.0));
    });

    it("returns base value raised to exponent float value", () => {
      const result = testedFun(Type.integer(4), Type.float(0.5));

      assert.deepStrictEqual(result, Type.float(2.0));
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

    it("raises ArithmeticError if the base is less than zero and exponent is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-7), Type.float(0.5)),
        "ArithmeticError",
        "bad argument in arithmetic expression",
      );
    });
  });
});

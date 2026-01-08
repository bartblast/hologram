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
});

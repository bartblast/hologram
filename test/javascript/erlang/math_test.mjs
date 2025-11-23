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
      assert.deepStrictEqual(testedFun(Type.float(1.23)), Type.float(2.0));
    });

    it("rounds negative float with fractional part up toward zero", () => {
      assert.deepStrictEqual(testedFun(Type.float(-1.23)), Type.float(-1.0));
    });

    it("keeps positive float without fractional part unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.float(1.0)), Type.float(1.0));
    });

    it("keeps negative float without fractional part unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.float(-1.0)), Type.float(-1.0));
    });

    it("keeps signed negative zero float unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.float(-0.0)), Type.float(0.0));
    });

    it("keeps signed positive zero float unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.float(+0.0)), Type.float(0.0));
    });

    it("keeps unsigned zero float unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.float(0.0)), Type.float(0.0));
    });

    it("keeps positive integer unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.integer(1)), Type.float(1.0));
    });

    it("keeps negative integer unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.integer(-1)), Type.float(-1.0));
    });

    it("keeps zero integer unchanged", () => {
      assert.deepStrictEqual(testedFun(Type.integer(0)), Type.float(0.0));
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });
});

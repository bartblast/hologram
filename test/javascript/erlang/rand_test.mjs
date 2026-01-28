"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Rand from "../../../assets/js/erlang/rand.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/rand_test.exs
// Always update both together.

describe("Erlang_Rand", () => {
  describe("uniform/0", () => {
    const uniform = Erlang_Rand["uniform/0"];

    it("returns a float in range [0.0, 1.0)", () => {
      const result = uniform();

      assert.isTrue(Type.isFloat(result));
      assert.isAtLeast(result.value, 0.0);
      assert.isBelow(result.value, 1.0);
    });
  });

  describe("uniform/1", () => {
    const uniform = Erlang_Rand["uniform/1"];

    it("positive integer argument returns integer between 1 and that argument", () => {
      const result = uniform(Type.integer(10));

      assert.isTrue(Type.isInteger(result));
      assert.isAtLeast(result.value, 1);
      assert.isAtMost(result.value, 10);
    });

    it("argument 1 returns 1", () => {
      const result = uniform(Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(1));
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if argument is a float", () => {
      const expectedMessage =
        "no function clause matching in :rand.uniform_s/2";

      assertBoxedError(
        () => uniform(Type.float(5.5)),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if argument is not a number", () => {
      const expectedMessage =
        "no function clause matching in :rand.uniform_s/2";

      assertBoxedError(
        () => uniform(Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if argument is zero", () => {
      const expectedMessage =
        "no function clause matching in :rand.uniform_s/2";

      assertBoxedError(
        () => uniform(Type.integer(0)),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if argument is negative", () => {
      const expectedMessage =
        "no function clause matching in :rand.uniform_s/2";

      assertBoxedError(
        () => uniform(Type.integer(-5)),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});

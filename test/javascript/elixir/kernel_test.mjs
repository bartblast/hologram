import {assert, linkModules, unlinkModules} from "../support/helpers.mjs";

import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Type from "../../../assets/js/type.mjs";

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/kernel_test.exs
// Always update both together.

describe("Elixir_Kernel", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("inspect/1", () => {
    const inspect = Elixir_Kernel["inspect/1"];

    it("delegates to inspect/2", () => {
      const result = inspect(Type.boolean(true));
      assert.deepStrictEqual(result, Type.bitstring("true"));
    });
  });

  // Important: keep Interpreter.inspect() consistency tests in sync.
  describe("inspect/2", () => {
    const inspect = Elixir_Kernel["inspect/2"];

    it("delegates to Interpreter.inspect()", () => {
      const result = inspect(Type.integer(123));
      assert.deepStrictEqual(result, Type.bitstring("123"));
    });
  });
});

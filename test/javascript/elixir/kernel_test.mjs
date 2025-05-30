import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/kernel_test.exs
// Always update both together.

describe("Elixir_Kernel", () => {
  describe("inspect/1", () => {
    const inspect = Elixir_Kernel["inspect/1"];

    it("delegates to inspect/2", () => {
      const result = inspect(Type.boolean(true));
      assert.deepStrictEqual(result, Type.bitstring("true"));
    });
  });

  // Also see Interpreter.inspect() consistency tests
  it("inspect/2", () => {
    const inspect = Elixir_Kernel["inspect/2"];

    const term = Type.map([
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("a"), Type.integer(1)],
    ]);

    const opts = Type.keywordList([
      [
        Type.atom("custom_options"),
        Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
      ],
    ]);

    const result = inspect(term, opts);
    const expected = Type.bitstring("%{a: 1, b: 2}");

    assert.deepStrictEqual(result, expected);
  });
});

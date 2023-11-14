import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Elixir_Kernel from "../../../assets/js/elixir/kernel.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/kernel_test.exs
// Always update both together.

describe("inspect/2", () => {
  describe("atom", () => {
    it("true", () => {
      const result = Elixir_Kernel["inspect/2"](
        Type.boolean(true),
        Type.list([]),
      );

      assert.deepStrictEqual(result, Type.bitstring("true"));
    });

    it("false", () => {
      const result = Elixir_Kernel["inspect/2"](
        Type.boolean(false),
        Type.list([]),
      );

      assert.deepStrictEqual(result, Type.bitstring("false"));
    });

    it("nil", () => {
      const result = Elixir_Kernel["inspect/2"](Type.nil(), Type.list([]));
      assert.deepStrictEqual(result, Type.bitstring("nil"));
    });

    it("non-boolean and non-nil", () => {
      const result = Elixir_Kernel["inspect/2"](
        Type.atom("abc"),
        Type.list([]),
      );

      assert.deepStrictEqual(result, Type.bitstring(":abc"));
    });
  });

  // TODO: remove when all types are supported
  it("default", () => {
    const result = Elixir_Kernel["inspect/2"]({type: "x"}, Type.list([]));
    assert.deepStrictEqual(result, Type.bitstring('{"type":"x"}'));
  });
});

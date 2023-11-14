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
  it("atom, true", () => {
    const result = Elixir_Kernel["inspect/2"](
      Type.boolean(true),
      Type.list([]),
    );

    assert.deepStrictEqual(result, Type.bitstring("true"));
  });

  it("atom, false", () => {
    const result = Elixir_Kernel["inspect/2"](
      Type.boolean(false),
      Type.list([]),
    );

    assert.deepStrictEqual(result, Type.bitstring("false"));
  });

  it("atom, nil", () => {
    const result = Elixir_Kernel["inspect/2"](Type.nil(), Type.list([]));
    assert.deepStrictEqual(result, Type.bitstring("nil"));
  });

  it("atom, non-boolean and non-nil", () => {
    const result = Elixir_Kernel["inspect/2"](Type.atom("abc"), Type.list([]));
    assert.deepStrictEqual(result, Type.bitstring(":abc"));
  });
});

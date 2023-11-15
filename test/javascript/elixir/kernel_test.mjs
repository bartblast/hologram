import {
  assert,
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

describe("inspect/1", () => {
  it("delegates to inspect/2", () => {
    const result = Elixir_Kernel["inspect/1"](Type.boolean(true));
    assert.deepStrictEqual(result, Type.bitstring("true"));
  });
});

// Important: keep Interpreter.inspect() consistency tests in sync.
describe("inspect/2", () => {
  it("delegates to Interpreter.inspect()", () => {
    const result = Elixir_Kernel["inspect/2"](Type.integer(123));
    assert.deepStrictEqual(result, Type.bitstring("123"));
  });
});

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../support/helpers.mjs";

import Elixir_Code from "../../../assets/js/elixir/code.mjs";
import Type from "../../../assets/js/type.mjs";

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/code_test.exs
// Always update both together.

describe("Elixir_Code", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("ensure_compiled/1", () => {
    const fun = Elixir_Code["ensure_compiled/1"];

    it("compiled module", () => {
      const module = Type.alias("String.Chars");
      const result = fun(module);
      const expected = Type.tuple([Type.atom("module"), module]);

      assert.deepStrictEqual(result, expected);
    });

    it("not compiled, non-existing module", () => {
      const module = Type.alias("MyModule");
      const result = fun(module);
      const expected = Type.tuple([Type.atom("error"), Type.atom("nofile")]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not an atom", () => {
      assertBoxedError(
        () => fun(Type.integer(1)),
        "FunctionClauseError",
        "no function clause matching in Code.ensure_compiled/1",
      );
    });
  });
});

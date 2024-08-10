import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Elixir_Code from "../../../assets/js/elixir/code.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/code_test.exs
// Always update both together.

describe("Elixir_Code", () => {
  describe("ensure_compiled/1", () => {
    const ensure_compiled = Elixir_Code["ensure_compiled/1"];

    it("compiled module", () => {
      const module = Type.alias("String.Chars");
      const result = ensure_compiled(module);
      const expected = Type.tuple([Type.atom("module"), module]);

      assert.deepStrictEqual(result, expected);
    });

    it("not compiled, non-existing module", () => {
      const module = Type.alias("MyModule");
      const result = ensure_compiled(module);
      const expected = Type.tuple([Type.atom("error"), Type.atom("nofile")]);

      assert.deepStrictEqual(result, expected);
    });

    // TODO: client error message for this case is inconsistent with server error message
    it("raises FunctionClauseError if the argument is not an atom", () => {
      assertBoxedError(
        () => ensure_compiled(Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("Code.ensure_compiled/1", [
          Type.integer(1),
        ]),
      );
    });
  });
});

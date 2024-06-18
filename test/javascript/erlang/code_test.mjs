"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Code from "../../../assets/js/erlang/code.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/code_test.exs
// Always update both together.

describe("Erlang_Code", () => {
  describe("ensure_loaded/1", () => {
    const ensure_loaded = Erlang_Code["ensure_loaded/1"];

    it("loaded module", () => {
      const module = Type.alias("String.Chars");
      const result = ensure_loaded(module);
      const expected = Type.tuple([Type.atom("module"), module]);

      assert.deepStrictEqual(result, expected);
    });

    it("not loaded, non-existing module", () => {
      const module = Type.alias("MyModule");
      const result = ensure_loaded(module);
      const expected = Type.tuple([Type.atom("error"), Type.atom("nofile")]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not an atom", () => {
      assertBoxedError(
        () => ensure_loaded(Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":code.ensure_loaded/1", [
          Type.integer(1),
        ]),
      );
    });
  });
});

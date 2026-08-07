import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Elixir_Code from "../../../assets/js/elixir/code.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the clause heads the compiler emits for the ported function, which
// the runtime script registers when the bundle loads.
Interpreter.defineFunctionClauseHeads("Code", "ensure_compiled", 1, "public", [
  {
    params: (_context) => [Type.variablePattern("module_0")],
    guards: [(context) => Erlang["is_atom/1"](context.vars.module_0)],
    blame: {
      params: ["module"],
      guards: [
        {
          source: "is_atom(module)",
          test: (context) => Erlang["is_atom/1"](context.vars.module_0),
        },
      ],
    },
  },
]);

Interpreter.defineFunctionClauseHeads("Code", "ensure_loaded", 1, "public", [
  {
    params: (_context) => [Type.variablePattern("module_0")],
    guards: [(context) => Erlang["is_atom/1"](context.vars.module_0)],
    blame: {
      params: ["module"],
      guards: [
        {
          source: "is_atom(module)",
          test: (context) => Erlang["is_atom/1"](context.vars.module_0),
        },
      ],
    },
  },
]);

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

    it("raises FunctionClauseError if the argument is not an atom", () => {
      assertBoxedError(
        () => ensure_compiled(Type.integer(1)),
        "FunctionClauseError",
        "no function clause matching in Code.ensure_compiled/1\n\nThe following arguments were given to Code.ensure_compiled/1:\n\n    # 1\n    1\n\nAttempted function clauses (showing 1 out of 1):\n\n    def ensure_compiled(module) when -is_atom(module)-\n",
      );
    });

    it("error frame carries args", () => {
      const module = Type.integer(1);

      let caught;

      try {
        ensure_compiled(module);
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "Code",
          function: "ensure_compiled",
          arityOrArgs: Type.list([module]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });

  describe("ensure_loaded/1", () => {
    const ensure_loaded = Elixir_Code["ensure_loaded/1"];

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
        "no function clause matching in Code.ensure_loaded/1\n\nThe following arguments were given to Code.ensure_loaded/1:\n\n    # 1\n    1\n\nAttempted function clauses (showing 1 out of 1):\n\n    def ensure_loaded(module) when -is_atom(module)-\n",
      );
    });

    it("error frame carries args", () => {
      const module = Type.integer(1);

      let caught;

      try {
        ensure_loaded(module);
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "Code",
          function: "ensure_loaded",
          arityOrArgs: Type.list([module]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });
});

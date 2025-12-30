"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
  freeze,
} from "../support/helpers.mjs";

import Erlang_Elixir_Locals from "../../../assets/js/erlang/elixir_locals.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomA = freeze(Type.atom("a"));
const atomB = freeze(Type.atom("b"));
const integer1 = freeze(Type.integer(1));
const integer2 = freeze(Type.integer(2));

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/elixir_locals_test.exs
// Always update both together.

describe("Erlang_Elixir_Locals", () => {
  describe("yank/2", () => {
    const yank = Erlang_Elixir_Locals["yank/2"];

    it("returns the removed value and updated locals as a tuple", () => {
      const locals = Type.map([
        [atomA, integer1],
        [atomB, integer2],
      ]);

      const result = yank(locals, atomB);
      const expected = Type.tuple([integer2, Type.map([[atomA, integer1]])]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error when the key is not present", () => {
      const locals = Type.map([[atomA, integer1]]);
      const result = yank(locals, atomB);

      assert.deepStrictEqual(result, Type.atom("error"));
    });

    it("raises BadMapError when the first argument is not a map", () => {
      assertBoxedError(
        () => yank(Type.atom("x"), atomB),
        "BadMapError",
        "expected a map, got: :x",
      );
    });
  });
});

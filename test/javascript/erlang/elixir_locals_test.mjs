"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Elixir_Locals from "../../../assets/js/erlang/elixir_locals.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/elixir_locals_test.exs
// Always update both together.

describe("Erlang_Elixir_Locals", () => {
  describe("yank/2", () => {
    const yank = Erlang_Elixir_Locals["yank/2"];

    it("returns the removed value and the map without the key", () => {
      const key = Type.atom("foo");
      const locals = Type.map([[key, Type.integer(1)]]);

      const result = yank(locals, key);

      const expected = Type.tuple([Type.integer(1), Type.map()]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error when the key is not present", () => {
      const locals = Type.map([[Type.atom("foo"), Type.integer(1)]]);
      const key = Type.atom("bar");

      const result = yank(locals, key);

      assert.deepStrictEqual(result, Type.atom("error"));
    });

    it("raises BadMapError when the first argument is not a map", () => {
      assertBoxedError(
        () => yank(Type.atom("abc"), Type.atom("foo")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });
});

"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
  freeze,
} from "../support/helpers.mjs";

import Erlang_Sets from "../../../assets/js/erlang/sets.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const integer1 = freeze(Type.integer(1));

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/sets_test.exs
// Always update both together.

describe("Erlang_Sets", () => {
  describe("to_list/1", () => {
    const to_list = Erlang_Sets["to_list/1"];

    it("returns an empty list if given an empty set", () => {
      const result = to_list(Type.map());
      assert.deepStrictEqual(result, Type.list());
    });

    it("returns a list of values if given a non-empty set", () => {
      const boolean = freeze(Type.boolean(false));
      const emptyList = freeze(Type.list([]));
      const bitstring = Type.bitstring("Hologram");

      const map = Type.map([
        [integer1, emptyList],
        [integer1, emptyList],
        [bitstring, emptyList],
        [boolean, emptyList],
      ]);

      const result = to_list(map);

      const expected = Type.list([integer1, bitstring, boolean]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a set", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.to_list/1",
        [Type.atom("abc")],
      );

      assertBoxedError(
        () => to_list(Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});

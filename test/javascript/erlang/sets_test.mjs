"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
  freeze,
} from "../support/helpers.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Erlang_Sets from "../../../assets/js/erlang/sets.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomAbc = freeze(Type.atom("abc"));
const emptyList = freeze(Type.list());
const integer1 = freeze(Type.integer(1));
const integer2 = freeze(Type.integer(2));
const integer3 = freeze(Type.integer(3));
const float2 = freeze(Type.float(2.0));

const versionTwoOpts = freeze(
  Type.list([Type.tuple([Type.atom("version"), Type.integer(2)])]),
);

const set123 = freeze(
  Type.map([
    [integer1, Type.list([])],
    [integer2, Type.list([])],
    [integer3, Type.list([])],
  ]),
);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/sets_test.exs
// Always update both together.

describe("Erlang_Sets", () => {
  describe("from_list/2", () => {
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("creates a set from an empty list with version 2 option", () => {
      const result = from_list_2(Type.list([]), versionTwoOpts);

      assert.deepStrictEqual(result, Type.map([]));
    });

    it("creates a set from a list with elements and version 2 option", () => {
      const list = Type.list([integer1, integer2, integer3]);
      const result = from_list_2(list, versionTwoOpts);

      assert.deepStrictEqual(result, set123);
    });

    it("creates a set from a list with duplicate elements", () => {
      const list = Type.list([integer1, integer2, integer1, integer3]);
      const result = from_list_2(list, versionTwoOpts);

      assert.deepStrictEqual(result, set123);
    });

    it("raises ArgumentError when list is not a list", () => {
      assertBoxedError(
        () => from_list_2(Type.atom("invalid"), versionTwoOpts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });

    it("raises ArgumentError when list is an improper list", () => {
      const list = Type.improperList([integer1, integer2]);

      assertBoxedError(
        () => from_list_2(list, versionTwoOpts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });
  });

  describe("new/1", () => {
    const new_1 = Erlang_Sets["new/1"];

    it("creates a new empty set with version 2 option", () => {
      const result = new_1(versionTwoOpts);
      const expected = Type.map([]);

      assert.deepStrictEqual(result, expected);
    });

    it("creates a new empty set with empty opts (defaults to version 2)", () => {
      const result = new_1(Type.list([]));
      const expected = Type.map([]);

      assert.deepStrictEqual(result, expected);
    });

    it("ignores invalid option keys", () => {
      const opts = Type.list([
        Type.tuple([Type.atom("invalid"), Type.integer(2)]),
      ]);
      const result = new_1(opts);
      const expected = Type.map([]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError when opts is not a list", () => {
      const opts = Type.atom("invalid");

      assertBoxedError(
        () => new_1(opts),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.new/1", [opts]),
      );
    });

    it("raises HologramInterpreterError when version is 1", () => {
      const opts = Type.list([
        Type.tuple([Type.atom("version"), Type.integer(1)]),
      ]);

      assert.throw(
        () => new_1(opts),
        HologramInterpreterError,
        ":sets version 1 is not supported in Hologram, use [{:version, 2}] option",
      );
    });

    it("raises CaseClauseError when version is invalid", () => {
      const version = Type.integer(3);
      const opts = Type.list([Type.tuple([Type.atom("version"), version])]);

      assertBoxedError(
        () => new_1(opts),
        "CaseClauseError",
        "no case clause matching: " + Interpreter.inspect(version),
      );
    });
  });

  describe("to_list/1", () => {
    const to_list = Erlang_Sets["to_list/1"];

    it("returns an empty list if given an empty set", () => {
      const set = Type.map();

      const result = to_list(set);

      assert.deepStrictEqual(result, emptyList);
    });

    it("returns a list of values if given a non-empty set", () => {
      const set = Type.map([
        [integer1, emptyList],
        [float2, emptyList],
      ]);

      const result = to_list(set);
      const sortedResult = Erlang_Lists["sort/1"](result);
      const expected = Type.list([integer1, float2]);

      assert.deepStrictEqual(sortedResult, expected);
    });

    it("raises FunctionClauseError if the argument is not a set", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.to_list/1",
        [atomAbc],
      );

      assertBoxedError(
        () => to_list(atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});

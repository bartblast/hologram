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
const opts = freeze(Type.keywordList([[Type.atom("version"), integer2]]));

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

    it("creates a set from an empty list", () => {
      const result = from_list_2(Type.list(), opts);

      assert.deepStrictEqual(result, Type.map());
    });

    it("creates a set from a non-empty list", () => {
      const list = Type.list([integer1, integer2, integer3]);
      const result = from_list_2(list, opts);

      assert.deepStrictEqual(result, set123);
    });

    it("creates a set from a list with duplicate elements", () => {
      const list = Type.list([integer1, integer2, integer1, integer3]);
      const result = from_list_2(list, opts);

      assert.deepStrictEqual(result, set123);
    });

    it("ignores invalid options", () => {
      const opts = Type.keywordList([
        [Type.atom("invalid"), integer1],
        [Type.atom("version"), integer2],
      ]);

      const result = from_list_2(emptyList, opts);

      assert.deepStrictEqual(result, Type.map());
    });

    it("raises ArgumentError if the first argument is not a list", () => {
      assertBoxedError(
        () => from_list_2(Type.atom("invalid"), opts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });

    it("raises ArgumentError if the first argument is an improper list", () => {
      const list = Type.improperList([integer1, integer2]);

      assertBoxedError(
        () => from_list_2(list, opts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });

    it("raises FunctionClauseError if the second argument is not a list", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":proplists.get_value/3",
        [Type.atom("version"), Type.atom("invalid"), integer1],
      );

      assertBoxedError(
        () => from_list_2(emptyList, Type.atom("invalid")),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the second argument is an a improper list", () => {
      const opts = Type.improperList([integer1, integer2]);

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":proplists.get_value/3",
      );

      assertBoxedError(
        () => from_list_2(emptyList, opts),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises CaseClauseError for invalid versions", () => {
      const opts = Type.keywordList([[Type.atom("version"), atomAbc]]);

      assertBoxedError(
        () => from_list_2(emptyList, opts),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    describe("client-only behaviour", () => {
      it("raises HologramInterpreterError if version 1 is used", () => {
        const opts = Type.keywordList([[Type.atom("version"), integer1]]);

        assert.throw(
          () => from_list_2(emptyList, opts),
          HologramInterpreterError,
          "Hologram doesn't support :sets version 1",
        );
      });

      it("raises HologramInterpreterError if version is not specified", () => {
        assert.throw(
          () => from_list_2(emptyList, emptyList),
          HologramInterpreterError,
          "Hologram requires to specify :sets version explicitely",
        );
      });
    });
  });

  describe("is_element/2", () => {
    const is_element_2 = Erlang_Sets["is_element/2"];

    it("returns true if element is in the set", () => {
      const result = is_element_2(integer2, set123);

      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("returns false if element is not in the set", () => {
      const integer42 = Type.integer(42);
      const result = is_element_2(integer42, set123);

      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("returns false for empty set", () => {
      const emptySet = Type.map();
      const result = is_element_2(Type.atom("any"), emptySet);

      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("raises FunctionClauseError if argument is not a set", () => {
      const elem = Type.atom("elem");
      const notASet = Type.atom("not_a_set");

      assertBoxedError(
        () => is_element_2(elem, notASet),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.is_element/2", [
          elem,
          notASet,
        ]),
      );
    });
  });

  describe("new/1", () => {
    const new_1 = Erlang_Sets["new/1"];

    it("creates a new set", () => {
      const result = new_1(opts);

      assert.deepStrictEqual(result, Type.map());
    });

    it("ignores invalid options", () => {
      const opts = Type.keywordList([
        [Type.atom("invalid"), integer1],
        [Type.atom("version"), integer2],
      ]);

      const result = new_1(opts);

      assert.deepStrictEqual(result, Type.map());
    });

    it("raises FunctionClauseError if the first argument is not a list", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":proplists.get_value/3",
        [Type.atom("version"), Type.atom("invalid"), integer1],
      );

      assertBoxedError(
        () => new_1(Type.atom("invalid")),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the first argument is an a improper list", () => {
      const opts = Type.improperList([integer1, integer2]);

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":proplists.get_value/3",
      );

      assertBoxedError(() => new_1(opts), "FunctionClauseError", expectedMsg);
    });

    it("raises CaseClauseError for invalid versions", () => {
      const opts = Type.keywordList([[Type.atom("version"), atomAbc]]);

      assertBoxedError(
        () => new_1(opts),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    describe("client-only behaviour", () => {
      it("raises HologramInterpreterError if version 1 is used", () => {
        const opts = Type.keywordList([[Type.atom("version"), integer1]]);

        assert.throw(
          () => new_1(opts),
          HologramInterpreterError,
          "Hologram doesn't support :sets version 1",
        );
      });

      it("raises HologramInterpreterError if version is not specified", () => {
        assert.throw(
          () => new_1(emptyList),
          HologramInterpreterError,
          "Hologram requires to specify :sets version explicitely",
        );
      });
    });
  });

  describe("to_list/1", () => {
    const to_list = Erlang_Sets["to_list/1"];

    it("returns an empty list if given an empty set", () => {
      const set = Erlang_Sets["new/1"](opts);
      const result = to_list(set);

      assert.deepStrictEqual(result, emptyList);
    });

    it("returns a list of values if given a non-empty set", () => {
      const set = Erlang_Sets["from_list/2"](
        Type.list([integer1, float2]),
        opts,
      );

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

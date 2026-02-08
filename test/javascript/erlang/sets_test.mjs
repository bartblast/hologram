"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  defineGlobalErlangAndElixirModules,
  freeze,
} from "../support/helpers.mjs";

import Erlang_Erlang from "../../../assets/js/erlang/erlang.mjs";
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
const float1 = freeze(Type.float(1.0));
const float2 = freeze(Type.float(2.0));

const opts = freeze(Type.keywordList([[Type.atom("version"), integer2]]));
const emptySet = freeze(Erlang_Sets["from_list/2"](Type.list(), opts));

const set123 = freeze(
  Erlang_Sets["from_list/2"](Type.list([integer1, integer2, integer3]), opts),
);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/sets_test.exs
// Always update both together.

describe("Erlang_Sets", () => {
  describe("add_element/2", () => {
    const add_element_2 = Erlang_Sets["add_element/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("adds a new element to the set", () => {
      const set = from_list_2(Type.list([integer1, integer3]), opts);
      const result = add_element_2(integer2, set);

      assert.deepStrictEqual(result, set123);
    });

    it("returns the same set if element is already present", () => {
      const result = add_element_2(integer2, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("adds element to empty set", () => {
      const emptySet = from_list_2(Type.list(), opts);

      const result = add_element_2(integer1, emptySet);
      const expected = from_list_2(Type.list([integer1]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("uses strict matching (integer vs float)", () => {
      const set = from_list_2(Type.list([float1]), opts);

      const result = add_element_2(integer1, set);
      const expected = from_list_2(Type.list([float1, integer1]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("doesn't mutate the original set", () => {
      const set = from_list_2(Type.list([integer1, integer2]), opts);

      add_element_2(integer3, set);

      const expected = from_list_2(Type.list([integer1, integer2]), opts);

      assert.deepStrictEqual(set, expected);
    });

    it("raises FunctionClauseError if argument is not a set", () => {
      const elem = Type.atom("elem");
      const notASet = Type.atom("not_a_set");

      assertBoxedError(
        () => add_element_2(elem, notASet),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.add_element/2", [
          elem,
          notASet,
        ]),
      );
    });
  });

  describe("del_element/2", () => {
    const del_element_2 = Erlang_Sets["del_element/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("removes an existing element from the set", () => {
      const result = del_element_2(integer2, set123);
      const expected = from_list_2(Type.list([integer1, integer3]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("returns the same set if element is not present", () => {
      const integer42 = Type.integer(42);
      const result = del_element_2(integer42, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("returns empty set when removing from empty set", () => {
      const emptySet = from_list_2(Type.list(), opts);
      const result = del_element_2(Type.atom("any"), emptySet);

      assert.deepStrictEqual(result, emptySet);
    });

    it("uses strict matching (integer vs float)", () => {
      const set = from_list_2(Type.list([integer2]), opts);
      const result = del_element_2(float2, set);

      assert.deepStrictEqual(result, set);
    });

    it("raises FunctionClauseError if argument is not a set", () => {
      const elem = Type.atom("elem");
      const notASet = Type.atom("not_a_set");

      assertBoxedError(
        () => del_element_2(elem, notASet),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.del_element/2", [
          elem,
          notASet,
        ]),
      );
    });
  });

  describe("filter/2", () => {
    const filter_2 = Erlang_Sets["filter/2"];

    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang[">/2"](context.vars.elem, integer2);
          },
        },
      ],
      contextFixture(),
    );

    it("filters elements from a non-empty set", () => {
      const result = filter_2(fun, set123);

      assert.deepStrictEqual(
        result,
        Erlang_Sets["from_list/2"](Type.list([integer3]), opts),
      );
    });

    it("returns an empty set if the predicate filters out all elements", () => {
      const filterAllFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Erlang[">/2"](context.vars.elem, Type.integer(10));
            },
          },
        ],
        contextFixture(),
      );

      const result = filter_2(filterAllFun, set123);

      assert.deepStrictEqual(
        result,
        Erlang_Sets["from_list/2"](Type.list(), opts),
      );
    });

    it("returns the same set if the predicate matches all elements", () => {
      const matchAllFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Erlang[">/2"](context.vars.elem, Type.integer(0));
            },
          },
        ],
        contextFixture(),
      );

      const result = filter_2(matchAllFun, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("filters elements from an empty set", () => {
      const emptySet = Erlang_Sets["new/1"](opts);
      const result = filter_2(fun, emptySet);

      assert.deepStrictEqual(
        result,
        Erlang_Sets["from_list/2"](Type.list(), opts),
      );
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.filter/2",
        [Type.atom("invalid"), set123],
      );

      assertBoxedError(
        () => filter_2(Type.atom("invalid"), set123),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the first argument is an anonymous function with wrong arity", () => {
      const wrongArityFun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("x"),
              Type.variablePattern("y"),
            ],
            guards: [],
            body: (context) => {
              return Erlang["==/2"](context.vars.x, context.vars.y);
            },
          },
        ],
        contextFixture(),
      );

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.filter/2",
        [wrongArityFun, set123],
      );

      assertBoxedError(
        () => filter_2(wrongArityFun, set123),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.filter/2",
        [fun, atomAbc],
      );

      assertBoxedError(
        () => filter_2(fun, atomAbc),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises ErlangError if the predicate does not return a boolean", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => {
              return Type.atom("not_a_boolean");
            },
          },
        ],
        contextFixture(),
      );

      const expectedMsg = Interpreter.buildErlangErrorMsg(
        `{:bad_filter, :not_a_boolean}`,
      );

      assertBoxedError(
        () => filter_2(badFun, set123),
        "ErlangError",
        expectedMsg,
      );
    });
  });

  describe("fold/3", () => {
    const fold_3 = Erlang_Sets["fold/3"];

    // Returns the accumulator unchanged (_elem, acc -> acc)
    const returnAccFun = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.matchPlaceholder(),
            Type.variablePattern("acc"),
          ],
          guards: [],
          body: (context) => {
            return context.vars.acc;
          },
        },
      ],
      contextFixture(),
    );

    it("folds over an empty set and returns the initial accumulator", () => {
      const set = Erlang_Sets["new/1"](opts);
      const result = fold_3(returnAccFun, integer1, set);

      assert.deepStrictEqual(result, integer1);
    });

    it("folds over a set with a single element", () => {
      const set = Erlang_Sets["from_list/2"](Type.list([integer2]), opts);

      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("elem"),
              Type.variablePattern("acc"),
            ],
            guards: [],
            body: (context) => {
              return Interpreter.consOperator(
                context.vars.elem,
                context.vars.acc,
              );
            },
          },
        ],
        contextFixture(),
      );

      const result = fold_3(fun, Type.list(), set);
      const expected = Type.list([integer2]);

      assert.deepStrictEqual(result, expected);
    });

    it("folds over a set with multiple elements", () => {
      const set = Erlang_Sets["from_list/2"](
        Type.list([integer1, integer2, integer3]),
        opts,
      );

      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("elem"),
              Type.variablePattern("acc"),
            ],
            guards: [],
            body: (context) => {
              return Erlang_Erlang["+/2"](context.vars.acc, context.vars.elem);
            },
          },
        ],
        contextFixture(),
      );

      const result = fold_3(fun, Type.integer(0), set);

      assert.deepStrictEqual(result, Type.integer(6));
    });

    it("raises FunctionClauseError if the first argument is not a function", () => {
      const set = Erlang_Sets["from_list/2"](
        Type.list([integer1, integer2, integer3]),
        opts,
      );

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.fold/3",
        [atomAbc, Type.integer(0), set],
      );

      assertBoxedError(
        () => fold_3(atomAbc, Type.integer(0), set),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the function has wrong arity", () => {
      const set = Erlang_Sets["from_list/2"](
        Type.list([integer1, integer2, integer3]),
        opts,
      );

      const fun = Type.anonymousFunction(
        1, // Wrong arity - should be 2
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return context.vars.elem;
            },
          },
        ],
        contextFixture(),
      );

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.fold/3",
        [fun, Type.integer(0), set],
      );

      assertBoxedError(
        () => fold_3(fun, Type.integer(0), set),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the third argument is not a set", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.fold/3",
        [returnAccFun, Type.integer(0), atomAbc],
      );

      assertBoxedError(
        () => fold_3(returnAccFun, Type.integer(0), atomAbc),
        "FunctionClauseError",
        expectedMsg,
      );
    });
  });

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

  describe("intersection/2", () => {
    const intersection_2 = Erlang_Sets["intersection/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("returns the intersection of two sets with common elements", () => {
      const set234 = from_list_2(
        Type.list([integer2, integer3, Type.integer(4)]),
        opts,
      );

      const result = intersection_2(set123, set234);
      const expected = from_list_2(Type.list([integer2, integer3]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("returns an empty set if sets have no common elements", () => {
      const set12 = from_list_2(Type.list([integer1, integer2]), opts);
      const set3 = from_list_2(Type.list([integer3]), opts);

      const result = intersection_2(set12, set3);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns an empty set if both sets are empty", () => {
      const result = intersection_2(emptySet, emptySet);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns an empty set if first set is empty", () => {
      const result = intersection_2(emptySet, set123);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns an empty set if second set is empty", () => {
      const result = intersection_2(set123, emptySet);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns the same set if sets are identical", () => {
      const result = intersection_2(set123, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("uses strict matching (integer vs float)", () => {
      const setInt = from_list_2(Type.list([integer1]), opts);
      const setFloat = from_list_2(Type.list([float1]), opts);

      const result = intersection_2(setInt, setFloat);

      assert.deepStrictEqual(result, emptySet);
    });

    it("raises FunctionClauseError if the first argument is not a set", () => {
      assertBoxedError(
        () => intersection_2(atomAbc, set123),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      assertBoxedError(
        () => intersection_2(set123, atomAbc),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });
  });

  describe("is_disjoint/2", () => {
    const is_disjoint_2 = Erlang_Sets["is_disjoint/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("returns true if sets have no common elements", () => {
      const set1 = from_list_2(Type.list([integer1, integer2]), opts);
      const set2 = from_list_2(Type.list([integer3]), opts);

      assertBoxedTrue(is_disjoint_2(set1, set2));
    });

    it("returns false if sets have common elements", () => {
      const set1 = from_list_2(Type.list([integer1, integer2]), opts);
      const set2 = from_list_2(Type.list([integer2, integer3]), opts);

      assertBoxedFalse(is_disjoint_2(set1, set2));
    });

    it("returns true if both sets are empty", () => {
      assertBoxedTrue(is_disjoint_2(emptySet, emptySet));
    });

    it("returns true if first set is empty", () => {
      assertBoxedTrue(is_disjoint_2(emptySet, set123));
    });

    it("returns true if second set is empty", () => {
      assertBoxedTrue(is_disjoint_2(set123, emptySet));
    });

    it("returns false if sets are identical", () => {
      assertBoxedFalse(is_disjoint_2(set123, set123));
    });

    it("uses strict matching (integer vs float)", () => {
      const setInt = from_list_2(Type.list([integer1]), opts);
      const setFloat = from_list_2(Type.list([float1]), opts);

      assertBoxedTrue(is_disjoint_2(setInt, setFloat));
    });

    it("raises FunctionClauseError if the first argument is not a set", () => {
      assertBoxedError(
        () => is_disjoint_2(atomAbc, set123),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      assertBoxedError(
        () => is_disjoint_2(set123, atomAbc),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });
  });

  describe("is_element/2", () => {
    const is_element_2 = Erlang_Sets["is_element/2"];

    it("returns true if element is in the set", () => {
      const result = is_element_2(integer2, set123);

      assertBoxedTrue(result);
    });

    it("returns false if element is not in the set", () => {
      const integer42 = Type.integer(42);
      const result = is_element_2(integer42, set123);

      assertBoxedFalse(result);
    });

    it("returns false for empty set", () => {
      const emptySet = Erlang_Sets["new/1"](opts);
      const result = is_element_2(Type.atom("any"), emptySet);

      assertBoxedFalse(result);
    });

    it("uses strict matching (integer vs float)", () => {
      const set = Erlang_Sets["from_list/2"](Type.list([integer1]), opts);
      const result = is_element_2(Type.float(1.0), set);

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
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

  describe("is_subset/2", () => {
    const is_subset = Erlang_Sets["is_subset/2"];

    it("returns true if all elements in first set are in second set", () => {
      const set12 = Erlang_Sets["from_list/2"](
        Type.list([Type.integer(1), Type.integer(2)]),
        opts,
      );

      const result = is_subset(set12, set123);

      assertBoxedTrue(result);
    });

    it("returns true if both sets are the same", () => {
      const result = is_subset(set123, set123);

      assertBoxedTrue(result);
    });

    it("returns true if both sets are empty", () => {
      const result = is_subset(emptySet, emptySet);

      assertBoxedTrue(result);
    });

    it("returns true if first set is empty and second set isn't", () => {
      const result = is_subset(emptySet, set123);

      assertBoxedTrue(result);
    });

    it("returns false if not all elements in first set are in second set", () => {
      const set14 = Erlang_Sets["from_list/2"](
        Type.list([Type.integer(1), Type.integer(4)]),
        opts,
      );

      const result = is_subset(set14, set123);

      assertBoxedFalse(result);
    });

    it("uses strict matching (integer vs float)", () => {
      const firstSet = Erlang_Sets["from_list/2"](Type.list([integer1]), opts);
      const secondSet = Erlang_Sets["from_list/2"](Type.list([float1]), opts);
      const result = is_subset(firstSet, secondSet);

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if the first argument is not a set", () => {
      const expectedMessage =
        Interpreter.buildFunctionClauseErrorMsg(":sets.fold/3");

      assertBoxedError(
        () => is_subset(atomAbc, set123),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.is_element/2",
        [Type.integer(1), atomAbc],
      );

      assertBoxedError(
        () => is_subset(set123, atomAbc),
        "FunctionClauseError",
        expectedMessage,
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

  describe("size/1", () => {
    const size = Erlang_Sets["size/1"];

    it("returns zero if given an empty set", () => {
      const set = Erlang_Sets["new/1"](opts);
      const result = size(set);

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns count for non-empty set", () => {
      const result = size(set123);

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("raises FunctionClauseError if the argument is not a set", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":sets.size/1",
        [atomAbc],
      );

      assertBoxedError(
        () => size(atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });

  describe("subtract/2", () => {
    const subtract_2 = Erlang_Sets["subtract/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("returns elements in the first set that are not in the second set", () => {
      const set234 = from_list_2(
        Type.list([integer2, integer3, Type.integer(4)]),
        opts,
      );

      const result = subtract_2(set123, set234);
      const expected = from_list_2(Type.list([integer1]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("returns the first set if sets have no common elements", () => {
      const set12 = from_list_2(Type.list([integer1, integer2]), opts);
      const set3 = from_list_2(Type.list([integer3]), opts);

      const result = subtract_2(set12, set3);

      assert.deepStrictEqual(result, set12);
    });

    it("returns an empty set if both sets are empty", () => {
      const result = subtract_2(emptySet, emptySet);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns an empty set if first set is empty", () => {
      const result = subtract_2(emptySet, set123);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns the first set if second set is empty", () => {
      const result = subtract_2(set123, emptySet);

      assert.deepStrictEqual(result, set123);
    });

    it("returns an empty set if sets are identical", () => {
      const result = subtract_2(set123, set123);

      assert.deepStrictEqual(result, emptySet);
    });

    it("uses strict matching (integer vs float)", () => {
      const setInt = from_list_2(Type.list([integer1]), opts);
      const setFloat = from_list_2(Type.list([float1]), opts);

      const result = subtract_2(setInt, setFloat);

      assert.deepStrictEqual(result, setInt);
    });

    it("raises FunctionClauseError if the first argument is not a set", () => {
      assertBoxedError(
        () => subtract_2(atomAbc, set123),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.filter/2"),
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      assertBoxedError(
        () => subtract_2(set123, atomAbc),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.is_element/2", [
          integer1,
          atomAbc,
        ]),
      );
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

  describe("union/2", () => {
    const union_2 = Erlang_Sets["union/2"];
    const from_list_2 = Erlang_Sets["from_list/2"];

    it("returns the union of two sets with some common elements", () => {
      const set234 = from_list_2(
        Type.list([integer2, integer3, Type.integer(4)]),
        opts,
      );

      const result = union_2(set123, set234);

      const expected = from_list_2(
        Type.list([integer1, integer2, integer3, Type.integer(4)]),
        opts,
      );

      assert.deepStrictEqual(result, expected);
    });

    it("returns the combined set if sets have no common elements", () => {
      const set12 = from_list_2(Type.list([integer1, integer2]), opts);
      const set3 = from_list_2(Type.list([integer3]), opts);

      const result = union_2(set12, set3);

      assert.deepStrictEqual(result, set123);
    });

    it("returns an empty set if both sets are empty", () => {
      const result = union_2(emptySet, emptySet);

      assert.deepStrictEqual(result, emptySet);
    });

    it("returns the second set if first set is empty", () => {
      const result = union_2(emptySet, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("returns the first set if second set is empty", () => {
      const result = union_2(set123, emptySet);

      assert.deepStrictEqual(result, set123);
    });

    it("returns the same set if sets are identical", () => {
      const result = union_2(set123, set123);

      assert.deepStrictEqual(result, set123);
    });

    it("uses strict matching (integer vs float)", () => {
      const setInt = from_list_2(Type.list([integer1]), opts);
      const setFloat = from_list_2(Type.list([float1]), opts);

      const result = union_2(setInt, setFloat);
      const expected = from_list_2(Type.list([integer1, float1]), opts);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not a set", () => {
      assertBoxedError(
        () => union_2(atomAbc, set123),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });

    it("raises FunctionClauseError if the second argument is not a set", () => {
      assertBoxedError(
        () => union_2(set123, atomAbc),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":sets.size/1", [atomAbc]),
      );
    });
  });
});

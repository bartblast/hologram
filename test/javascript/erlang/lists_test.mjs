"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const emptyList = Type.list();

const improperList = Type.improperList([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

const properList = Type.list([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

const funArity2 = Type.anonymousFunction(
  2,
  [
    {
      params: (_context) => [
        Type.variablePattern("x"),
        Type.variablePattern("y"),
      ],
      guards: [],
      body: (context) => {
        return Erlang["+/2"](context.vars.x, context.vars.y);
      },
    },
  ],
  contextFixture(),
);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/lists_test.exs
// Always update both together.

describe("Erlang_Lists", () => {
  describe("all/2", () => {
    const all = Erlang_Lists["all/2"];

    const fun = Type.anonymousFunction(
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

    it("returns true for empty list", () => {
      const result = all(fun, Type.list());

      assertBoxedTrue(result);
    });

    it("returns true when all elements satisfy predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = all(fun, list);

      assertBoxedTrue(result);
    });

    it("returns false when some elements don't satisfy predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(0), Type.integer(3)]);
      const result = all(fun, list);

      assertBoxedFalse(result);
    });

    it("returns false when no elements satisfy predicate", () => {
      const list = Type.list([Type.integer(0), Type.integer(-1), Type.integer(-2)]);
      const result = all(fun, list);

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if first arg is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.all/2",
        [Type.atom("abc"), Type.list()],
      );

      assertBoxedError(
        () => all(Type.atom("abc"), Type.list()),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if first arg has wrong arity", () => {
      const funArity2 = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("x"),
              Type.variablePattern("y"),
            ],
            guards: [],
            body: (context) => {
              return Erlang["+/2"](context.vars.x, context.vars.y);
            },
          },
        ],
        contextFixture(),
      );

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.all/2",
        [funArity2, Type.list()],
      );

      assertBoxedError(
        () => all(funArity2, Type.list()),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if second arg is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.all/2",
        [fun, Type.atom("abc")],
      );

      assertBoxedError(
        () => all(fun, Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if second arg is not a proper list", () => {
      const improperList = Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(":lists.all_1/2");

      assertBoxedError(
        () => all(fun, improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ErlangError if predicate doesn't return boolean", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Type.integer(42);
            },
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => all(badFun, Type.list([Type.integer(1)])),
        "ErlangError",
        Interpreter.buildErlangErrorMsg("{:bad_filter, 42}"),
      );
    });
  });

  describe("any/2", () => {
    const any = Erlang_Lists["any/2"];

    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang[">/2"](context.vars.elem, Type.integer(2));
          },
        },
      ],
      contextFixture(),
    );

    it("returns false for empty list", () => {
      const result = any(fun, Type.list());

      assertBoxedFalse(result);
    });

    it("returns true when some elements satisfy predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = any(fun, list);

      assertBoxedTrue(result);
    });

    it("returns true when all elements satisfy predicate", () => {
      const list = Type.list([Type.integer(3), Type.integer(4), Type.integer(5)]);
      const result = any(fun, list);

      assertBoxedTrue(result);
    });

    it("returns false when no elements satisfy predicate", () => {
      const list = Type.list([Type.integer(0), Type.integer(1), Type.integer(2)]);
      const result = any(fun, list);

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if first arg is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.any/2",
        [Type.atom("abc"), Type.list()],
      );

      assertBoxedError(
        () => any(Type.atom("abc"), Type.list()),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if first arg has wrong arity", () => {
      const funArity2 = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("x"),
              Type.variablePattern("y"),
            ],
            guards: [],
            body: (context) => {
              return Erlang["+/2"](context.vars.x, context.vars.y);
            },
          },
        ],
        contextFixture(),
      );

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.any/2",
        [funArity2, Type.list()],
      );

      assertBoxedError(
        () => any(funArity2, Type.list()),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if second arg is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.any/2",
        [fun, Type.atom("abc")],
      );

      assertBoxedError(
        () => any(fun, Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if second arg is not a proper list", () => {
      const improperList = Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(":lists.any_1/2");

      assertBoxedError(
        () => any(fun, improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ErlangError if predicate doesn't return boolean", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Type.integer(42);
            },
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => any(badFun, Type.list([Type.integer(1)])),
        "ErlangError",
        Interpreter.buildErlangErrorMsg("{:bad_filter, 42}"),
      );
    });
  });

  describe("append/1", () => {
    const testedFun = Erlang_Lists["append/1"];

    it("appends list of lists", () => {
      const listOfLists = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3), Type.integer(4)]),
        Type.list([Type.integer(5)]),
      ]);
      const result = testedFun(listOfLists);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
          Type.integer(5),
        ]),
      );
    });

    it("handles empty list of lists", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("handles list containing empty lists", () => {
      const listOfLists = Type.list([
        Type.list([]),
        Type.list([Type.integer(1)]),
        Type.list([]),
      ]);
      const result = testedFun(listOfLists);

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([Type.list([]), Type.list([])]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [
          Type.improperList([Type.list([]), Type.list([])]),
        ]),
      );
    });

    it("raises FunctionClauseError if list contains non-list", () => {
      assertBoxedError(
        () => testedFun(Type.list([Type.list([]), Type.atom("abc")])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append_1/2"),
      );
    });
  });

  describe("append/2", () => {
    const testedFun = Erlang_Lists["append/2"];

    it("appends two lists", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(2)]);
      const list2 = Type.list([Type.integer(3), Type.integer(4)]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]),
      );
    });

    it("appends to empty list", () => {
      const list1 = Type.list([]);
      const list2 = Type.list([Type.integer(1)]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
    });

    it("appends empty list", () => {
      const list1 = Type.list([Type.integer(1)]);
      const list2 = Type.list([]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          Type.atom("abc"),
          Type.list([]),
        ]),
      );
    });

    it("raises FunctionClauseError if first list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([Type.integer(1), Type.integer(2)]),
            Type.list([]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
          Type.list([]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.list([]), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          Type.list([]),
          Type.atom("abc"),
        ]),
      );
    });
  });

  describe("delete/2", () => {
    const testedFun = Erlang_Lists["delete/2"];

    it("deletes first occurrence of element", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(2),
      ]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(3), Type.integer(2)]),
      );
    });

    it("returns same list if element not found", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(3), list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(Type.integer(1), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("deletes from single element list", () => {
      const list = Type.list([Type.integer(1)]);
      const result = testedFun(Type.integer(1), list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
          Type.integer(1),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.integer(1),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
          Type.integer(1),
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });
  });

  describe("duplicate/2", () => {
    const testedFun = Erlang_Lists["duplicate/2"];

    it("duplicates element N times", () => {
      const result = testedFun(Type.integer(3), Type.atom("a"));

      assert.deepStrictEqual(
        result,
        Type.list([Type.atom("a"), Type.atom("a"), Type.atom("a")]),
      );
    });

    it("handles N = 0", () => {
      const result = testedFun(Type.integer(0), Type.atom("a"));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("handles N = 1", () => {
      const result = testedFun(Type.integer(1), Type.integer(42));

      assert.deepStrictEqual(result, Type.list([Type.integer(42)]));
    });

    it("duplicates different types", () => {
      const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(2), tuple);

      assert.deepStrictEqual(result, Type.list([tuple, tuple]));
    });

    it("raises FunctionClauseError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [
          Type.atom("abc"),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError if N is negative", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-1), Type.atom("a")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [
          Type.integer(-1),
          Type.atom("a"),
        ]),
      );
    });
  });

  describe("filter/2", () => {
    const filter = Erlang_Lists["filter/2"];

    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang[">/2"](context.vars.elem, Type.integer(1));
          },
        },
      ],
      contextFixture(),
    );

    it("empty list", () => {
      const result = filter(fun, Type.list());

      assert.deepStrictEqual(result, emptyList);
    });

    it("non-empty list", () => {
      const result = filter(fun, properList);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(2), Type.integer(3)]),
      );
    });

    it("first arg is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.filter/2",
        [Type.atom("abc"), properList],
      );

      assertBoxedError(
        () => filter(Type.atom("abc"), properList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("first arg is an anonymous function with arity different than 1", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.filter/2",
        [funArity2, properList],
      );

      assertBoxedError(
        () => filter(funArity2, properList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("second arg is not a list", () => {
      const expectedMessage = Interpreter.buildErlangErrorMsg(
        "{:bad_generator, :abc}",
      );

      assertBoxedError(
        () => filter(fun, Type.atom("abc")),
        "ErlangError",
        expectedMessage,
      );
    });

    it("second arg is not a proper list", () => {
      const expectedMessage = Interpreter.buildErlangErrorMsg(
        "{:bad_generator, 3}",
      );

      assertBoxedError(
        () => filter(fun, improperList),
        "ErlangError",
        expectedMessage,
      );
    });

    it("filter fun doesn't return a boolean", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Erlang["*/2"](Type.integer(2), context.vars.elem);
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      const expectedMessage =
        Interpreter.buildErlangErrorMsg("{:bad_filter, 4}");

      assertBoxedError(() => filter(fun, list), "ErlangError", expectedMessage);
    });
  });

  describe("flatten/1", () => {
    const flatten = Erlang_Lists["flatten/1"];

    it("works with empty list", () => {
      const result = flatten(emptyList);
      assert.deepStrictEqual(result, emptyList);
    });

    it("works with non-nested list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = flatten(list);

      assert.deepStrictEqual(result, list);
    });

    it("works with nested list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.list([
          Type.integer(2),
          Type.list([Type.integer(3), Type.integer(4), Type.integer(5)]),
          Type.integer(6),
        ]),
        Type.integer(7),
      ]);

      const result = flatten(list);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      const arg = Type.atom("abc");

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/1",
        [arg],
      );

      assertBoxedError(
        () => flatten(arg),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the argument is an improper list", () => {
      const arg = Type.improperList([
        Type.integer(1),
        Type.list([Type.integer(2), Type.integer(3)]),
        Type.integer(4),
        Type.integer(5),
      ]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/1",
        [arg],
      );

      assertBoxedError(
        () => flatten(arg),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the argument contains a nested improper list", () => {
      const nestedImproperList = Type.improperList([
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      const arg = Type.list([
        Type.integer(1),
        nestedImproperList,
        Type.integer(5),
      ]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/1",
        [nestedImproperList],
      );

      assertBoxedError(
        () => flatten(arg),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });

  describe("flatmap/2", () => {
    const testedFun = Erlang_Lists["flatmap/2"];

    const duplicateFun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Type.list([context.vars.elem, context.vars.elem]);
          },
        },
      ],
      contextFixture(),
    );

    it("maps and flattens the result", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(duplicateFun, list);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(1),
          Type.integer(2),
          Type.integer(2),
          Type.integer(3),
          Type.integer(3),
        ]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(duplicateFun, Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("flattens empty lists returned by function", () => {
      const emptyFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.list([]),
          },
        ],
        contextFixture(),
      );

      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(emptyFun, list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a 1-arity function", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (_context) => Type.list([]),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap/2", [
          fun,
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(duplicateFun, Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap/2", [
          duplicateFun,
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            duplicateFun,
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
      );
    });

    it("raises FunctionClauseError if function returns non-list", () => {
      const atomFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.atom("abc"),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(atomFun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
      );
    });

    it("raises FunctionClauseError if function returns improper list", () => {
      const improperFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) =>
              Type.improperList([Type.integer(1), Type.integer(2)]),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(improperFun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
      );
    });
  });

  describe("foldl/3", () => {
    const foldl = Erlang_Lists["foldl/3"];

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
            return Erlang["+/2"](context.vars.acc, context.vars.elem);
          },
        },
      ],
      contextFixture(),
    );

    const acc = Type.integer(0);

    it("reduces empty list", () => {
      const result = foldl(fun, acc, emptyList);
      assert.deepStrictEqual(result, acc);
    });

    it("reduces non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = foldl(fun, acc, list);

      assert.deepStrictEqual(result, Type.integer(6));
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.foldl/3",
        [Type.atom("abc"), acc, emptyList],
      );

      assertBoxedError(
        () => foldl(Type.atom("abc"), acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 2", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return context.vars.x;
            },
          },
        ],
        contextFixture(),
      );

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.foldl/3",
        [fun, acc, emptyList],
      );

      assertBoxedError(
        () => foldl(fun, acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises CaseClauseError if the third argument is not a list", () => {
      assertBoxedError(
        () => foldl(fun, acc, Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the third argument is an improper list", () => {
      assertBoxedError(
        () =>
          foldl(
            fun,
            acc,
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldl_1/3"),
      );
    });
  });

  describe("foreach/2", () => {
    const testedFun = Erlang_Lists["foreach/2"];

    it("calls function for each element and returns :ok", () => {
      const results = [];
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              results.push(context.vars.elem);
              return Type.atom("ok");
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(fun, list);

      assert.deepStrictEqual(result, Type.atom("ok"));
      assert.deepStrictEqual(results, [
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
    });

    it("handles empty list", () => {
      const results = [];
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              results.push(context.vars.elem);
              return Type.atom("ok");
            },
          },
        ],
        contextFixture(),
      );

      const result = testedFun(fun, Type.list([]));

      assert.deepStrictEqual(result, Type.atom("ok"));
      assert.deepStrictEqual(results, []);
    });

    it("raises FunctionClauseError if first argument is not a 1-arity function", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (_context) => Type.atom("ok"),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach/2", [
          fun,
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.atom("ok"),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach/2", [
          fun,
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.atom("ok"),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () =>
          testedFun(
            fun,
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach_1/2"),
      );
    });
  });

  describe("foldr/3", () => {
    const testedFun = Erlang_Lists["foldr/3"];

    const subtractFun = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("elem"),
            Type.variablePattern("acc"),
          ],
          guards: [],
          body: (context) => {
            return Erlang["-/2"](context.vars.elem, context.vars.acc);
          },
        },
      ],
      contextFixture(),
    );

    it("folds list from right to left", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(subtractFun, Type.integer(0), list);

      // (1 - (2 - (3 - 0))) = (1 - (2 - 3)) = (1 - (-1)) = 2
      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("handles empty list", () => {
      const result = testedFun(subtractFun, Type.integer(42), Type.list([]));

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("handles single element list", () => {
      const list = Type.list([Type.integer(5)]);
      const result = testedFun(subtractFun, Type.integer(3), list);

      // (5 - 3) = 2
      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("raises FunctionClauseError if first argument is not a 2-arity function", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.integer(1),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.integer(0), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr/3", [
          fun,
          Type.integer(0),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises CaseClauseError if third argument is not a list", () => {
      assertBoxedError(
        () => testedFun(subtractFun, Type.integer(0), Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            subtractFun,
            Type.integer(0),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr_1/3"),
      );
    });
  });

  describe("keyfind/3", () => {
    const keyfind = Erlang_Lists["keyfind/3"];

    it("returns the tuple that contains the given value at the given one-based index", () => {
      const tuple = Type.tuple([
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      const tuples = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.atom("abc"),
        tuple,
      ]);

      const result = keyfind(Type.integer(7), Type.integer(3), tuples);

      assert.deepStrictEqual(result, tuple);
    });

    it("returns false if there is no tuple that fulfills the given conditions", () => {
      const result = keyfind(
        Type.integer(7),
        Type.integer(3),
        Type.list([Type.atom("abc")]),
      );

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.atom("xyz"), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.integer(0), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is not a list", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.integer(1), Type.atom("xyz")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is an improper list", () => {
      assertBoxedError(
        () =>
          keyfind(
            Type.integer(7),
            Type.integer(4),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    });
  });

  describe("keymember/3", () => {
    const keymember = Erlang_Lists["keymember/3"];

    it("returns true if there is a tuple that fulfills the given conditions", () => {
      const tuple = Type.tuple([
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      const tuples = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.atom("abc"),
        tuple,
      ]);

      const result = keymember(Type.integer(7), Type.integer(3), tuples);

      assertBoxedTrue(result);
    });

    it("returns false if there is no tuple that fulfills the given conditions", () => {
      const result = keymember(
        Type.integer(7),
        Type.integer(3),
        Type.list([Type.atom("abc")]),
      );

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.atom("xyz"), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.integer(0), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is not a list", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.integer(1), Type.atom("xyz")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is an improper list", () => {
      assertBoxedError(
        () =>
          keymember(
            Type.integer(7),
            Type.integer(4),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    });
  });

  describe("last/1", () => {
    const testedFun = Erlang_Lists["last/1"];

    it("returns last element", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("returns element from single element list", () => {
      const list = Type.list([Type.atom("a")]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.atom("a"));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if list is empty", () => {
      assertBoxedError(
        () => testedFun(Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [
          Type.list([]),
        ]),
      );
    });
  });

  describe("map/2", () => {
    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang["*/2"](context.vars.elem, Type.integer(10));
          },
        },
      ],
      contextFixture(),
    );

    const map = Erlang_Lists["map/2"];

    it("maps empty list", () => {
      const result = map(fun, emptyList);
      assert.deepStrictEqual(result, emptyList);
    });

    it("maps non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = map(fun, list);

      const expected = Type.list([
        Type.integer(10),
        Type.integer(20),
        Type.integer(30),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.map/2",
        [Type.atom("abc"), emptyList],
      );

      assertBoxedError(
        () => map(Type.atom("abc"), emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 1", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.map/2",
        [funArity2, emptyList],
      );

      assertBoxedError(
        () => map(funArity2, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises CaseClauseError if the second argument is not a list", () => {
      assertBoxedError(
        () => map(fun, Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the second argument is an improper list", () => {
      assertBoxedError(
        () =>
          map(
            fun,
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.map_1/2"),
      );
    });
  });

  describe("max/1", () => {
    const testedFun = Erlang_Lists["max/1"];

    it("returns maximum from list of integers", () => {
      const list = Type.list([
        Type.integer(3),
        Type.integer(1),
        Type.integer(5),
        Type.integer(2),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns maximum from list of floats", () => {
      const list = Type.list([
        Type.float(3.5),
        Type.float(1.2),
        Type.float(5.9),
        Type.float(2.1),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(5.9));
    });

    it("returns maximum from mixed number types", () => {
      const list = Type.list([
        Type.integer(3),
        Type.float(3.1),
        Type.integer(2),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(3.1));
    });

    it("returns single element from list with one element", () => {
      const list = Type.list([Type.integer(42)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises ArgumentError if list is empty", () => {
      assertBoxedError(
        () => testedFun(Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "[]"),
      );
    });
  });

  describe("min/1", () => {
    const testedFun = Erlang_Lists["min/1"];

    it("returns minimum from list of integers", () => {
      const list = Type.list([
        Type.integer(3),
        Type.integer(1),
        Type.integer(5),
        Type.integer(2),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("returns minimum from list of floats", () => {
      const list = Type.list([
        Type.float(3.5),
        Type.float(1.2),
        Type.float(5.9),
        Type.float(2.1),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(1.2));
    });

    it("returns minimum from mixed number types", () => {
      const list = Type.list([
        Type.integer(3),
        Type.float(2.9),
        Type.integer(4),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(2.9));
    });

    it("returns single element from list with one element", () => {
      const list = Type.list([Type.integer(42)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises ArgumentError if list is empty", () => {
      assertBoxedError(
        () => testedFun(Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "[]"),
      );
    });
  });

  describe("nth/2", () => {
    const testedFun = Erlang_Lists["nth/2"];

    it("returns first element with index 1", () => {
      const list = Type.list([
        Type.integer(10),
        Type.integer(20),
        Type.integer(30),
      ]);
      const result = testedFun(Type.integer(1), list);

      assert.deepStrictEqual(result, Type.integer(10));
    });

    it("returns middle element", () => {
      const list = Type.list([
        Type.integer(10),
        Type.integer(20),
        Type.integer(30),
      ]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(result, Type.integer(20));
    });

    it("returns last element", () => {
      const list = Type.list([
        Type.integer(10),
        Type.integer(20),
        Type.integer(30),
      ]);
      const result = testedFun(Type.integer(3), list);

      assert.deepStrictEqual(result, Type.integer(30));
    });

    it("raises FunctionClauseError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [
          Type.atom("abc"),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [
          Type.integer(1),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.integer(1),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [
          Type.integer(1),
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if index is less than 1", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [
          Type.integer(0),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if index is greater than list length", () => {
      assertBoxedError(
        () => testedFun(Type.integer(4), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [
          Type.integer(4),
          Type.list([Type.integer(1)]),
        ]),
      );
    });
  });

  describe("nthtail/2", () => {
    const testedFun = Erlang_Lists["nthtail/2"];

    it("returns list with N=0 (no change)", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(0), list);

      assert.deepStrictEqual(result, list);
    });

    it("returns tail after 1 element", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(1), list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(2), Type.integer(3)]),
      );
    });

    it("returns tail after 2 elements", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(result, Type.list([Type.integer(3)]));
    });

    it("returns empty list when dropping all elements", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [
          Type.atom("abc"),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [
          Type.integer(1),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if N is negative", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-1), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [
          Type.integer(-1),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if N is greater than list length", () => {
      assertBoxedError(
        () => testedFun(Type.integer(3), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [
          Type.integer(3),
          Type.list([Type.integer(1)]),
        ]),
      );
    });
  });

  describe("member/2", () => {
    const member = Erlang_Lists["member/2"];

    it("is a member of a proper list", () => {
      const result = member(Type.integer(2), properList);
      assertBoxedTrue(result);
    });

    it("is a non-last member of an improper list", () => {
      const result = member(Type.integer(2), improperList);
      assertBoxedTrue(result);
    });

    it("is the last member of an improper list", () => {
      assertBoxedError(
        () => member(Type.integer(3), improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });

    it("is not a member of a proper list", () => {
      const result = member(Type.integer(4), properList);
      assertBoxedFalse(result);
    });

    it("is not a member of an improper list", () => {
      assertBoxedError(
        () => member(Type.integer(4), improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });

    it("uses strict equality", () => {
      const list = Type.list([
        Type.integer(1),
        Type.float(2.0),
        Type.integer(3),
      ]);
      const result = member(Type.integer(2), list);

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument is not a list", () => {
      assertBoxedError(
        () => member(Type.integer(2), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    });
  });

  describe("reverse/1", () => {
    const reverse = Erlang_Lists["reverse/1"];

    it("returns a list with the elements in the argument in reverse order", () => {
      const result = reverse(properList);

      const expected = Type.list([
        Type.integer(3),
        Type.integer(2),
        Type.integer(1),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.reverse/1",
        [Type.atom("abc")],
      );

      assertBoxedError(
        () => reverse(Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ArgumentError if the argument is not a proper list", () => {
      assertBoxedError(
        () => reverse(improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("reverse/2", () => {
    const reverse = Erlang_Lists["reverse/2"];

    const integer1 = Type.integer(1);
    const integer2 = Type.integer(2);
    const integer3 = Type.integer(3);
    const integer4 = Type.integer(4);
    const integer5 = Type.integer(5);

    const list12 = Type.list([integer1, integer2]);
    const list34 = Type.list([integer3, integer4]);

    const improperList12 = Type.improperList([integer1, integer2]);
    const improperList34 = Type.improperList([integer3, integer4]);

    describe("1st arg = [1, 2]", () => {
      it("2nd arg = [3, 4]", () => {
        const expected = Type.list([integer2, integer1, integer3, integer4]);
        assert.deepStrictEqual(reverse(list12, list34), expected);
      });

      it("2nd arg = [3 | 4]", () => {
        const expected = Type.improperList([
          integer2,
          integer1,
          integer3,
          integer4,
        ]);
        assert.deepStrictEqual(reverse(list12, improperList34), expected);
      });

      it("2nd arg = []", () => {
        const expected = Type.list([integer2, integer1]);
        assert.deepStrictEqual(reverse(list12, emptyList), expected);
      });

      it("2nd arg = 5", () => {
        const expected = Type.improperList([integer2, integer1, integer5]);
        assert.deepStrictEqual(reverse(list12, integer5), expected);
      });
    });

    it("1st arg is an improper list", () => {
      assertBoxedError(
        () => reverse(improperList12, list34),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });

    describe("1st arg = []", () => {
      it("2nd arg = [3, 4]", () => {
        assert.deepStrictEqual(reverse(emptyList, list34), list34);
      });

      it("2nd arg = [3 | 4]", () => {
        assert.deepStrictEqual(
          reverse(emptyList, improperList34),
          improperList34,
        );
      });

      it("2nd arg = []", () => {
        assert.deepStrictEqual(reverse(emptyList, emptyList), emptyList);
      });

      it("2nd arg = 5", () => {
        assert.deepStrictEqual(reverse(emptyList, integer5), integer5);
      });
    });

    it("1st arg is not a list", () => {
      assertBoxedError(
        () => reverse(integer5, list34),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("sort/1", () => {
    const sort = Erlang_Lists["sort/1"];

    it("sorts items in the list", () => {
      const list = Type.list([
        Type.atom("a"),
        Type.integer(4),
        Type.float(3.0),
        Type.atom("b"),
        Type.integer(1),
        Type.float(2.0),
      ]);

      assert.deepStrictEqual(
        sort(list),
        Type.list([
          Type.integer(1),
          Type.float(2.0),
          Type.float(3.0),
          Type.integer(4),
          Type.atom("a"),
          Type.atom("b"),
        ]),
      );
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.sort/1",
        [Type.atom("abc")],
      );

      assertBoxedError(
        () => sort(Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client error message is intentionally different than server error message.
    it("raises FunctionClauseError if the argument is an improper list", () => {
      assertBoxedError(
        () => sort(improperList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split_1/5"),
      );
    });
  });

  describe("split/2", () => {
    const testedFun = Erlang_Lists["split/2"];

    it("splits list at given position", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([Type.integer(3), Type.integer(4)]),
        ]),
      );
    });

    it("splits at beginning (N=0)", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(0), list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([]),
          Type.list([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("splits at end (N=length)", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(2), list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([]),
        ]),
      );
    });

    it("splits empty list", () => {
      const result = testedFun(Type.integer(0), Type.list([]));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.list([]), Type.list([])]),
      );
    });

    it("raises FunctionClauseError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [
          Type.atom("abc"),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [
          Type.integer(1),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.integer(1),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [
          Type.integer(1),
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if N is negative", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-1), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [
          Type.integer(-1),
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if N is greater than list length", () => {
      assertBoxedError(
        () => testedFun(Type.integer(3), Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [
          Type.integer(3),
          Type.list([Type.integer(1)]),
        ]),
      );
    });
  });

  describe("sublist/2", () => {
    const testedFun = Erlang_Lists["sublist/2"];

    it("returns first N elements", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(list, Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns entire list when N equals length", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns entire list when N exceeds length", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.integer(5));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns empty list when N is 0", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.integer(0));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          Type.atom("abc"),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.list([Type.integer(1)]), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          Type.list([Type.integer(1)]),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if N is negative", () => {
      assertBoxedError(
        () => testedFun(Type.list([Type.integer(1)]), Type.integer(-1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          Type.list([Type.integer(1)]),
          Type.integer(-1),
        ]),
      );
    });
  });

  describe("sublist/3", () => {
    const testedFun = Erlang_Lists["sublist/3"];

    it("returns sublist from start position with given length", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(list, Type.integer(2), Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(2), Type.integer(3)]),
      );
    });

    it("returns sublist from beginning", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(list, Type.integer(1), Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns empty list when length is 0", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.integer(1), Type.integer(0));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("returns empty list when start is beyond list length", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.integer(5), Type.integer(2));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("returns partial list when length exceeds remaining elements", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(list, Type.integer(2), Type.integer(5));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(2), Type.integer(3)]),
      );
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(1), Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          Type.atom("abc"),
          Type.integer(1),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError if start is not an integer", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1)]),
            Type.atom("abc"),
            Type.integer(1),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          Type.list([Type.integer(1)]),
          Type.atom("abc"),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError if length is not an integer", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1)]),
            Type.integer(1),
            Type.atom("abc"),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          Type.list([Type.integer(1)]),
          Type.integer(1),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if start is less than 1", () => {
      assertBoxedError(
        () =>
          testedFun(Type.list([Type.integer(1)]), Type.integer(0), Type.integer(1)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          Type.list([Type.integer(1)]),
          Type.integer(0),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError if length is negative", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1)]),
            Type.integer(1),
            Type.integer(-1),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          Type.list([Type.integer(1)]),
          Type.integer(1),
          Type.integer(-1),
        ]),
      );
    });
  });

  describe("takewhile/2", () => {
    const testedFun = Erlang_Lists["takewhile/2"];

    const lessThan3 = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang["</2"](context.vars.elem, Type.integer(3));
          },
        },
      ],
      contextFixture(),
    );

    it("takes elements while predicate is true", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns empty list when first element fails predicate", () => {
      const list = Type.list([Type.integer(5), Type.integer(1)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("returns entire list when all elements pass predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns empty list for empty input", () => {
      const result = testedFun(lessThan3, Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a 1-arity function", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (_context) => Type.boolean(true),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile/2", [
          fun,
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(lessThan3, Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile/2", [
          lessThan3,
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if function returns non-boolean", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.integer(42),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(badFun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile_2/4"),
      );
    });
  });

  describe("dropwhile/2", () => {
    const testedFun = Erlang_Lists["dropwhile/2"];

    const lessThan3 = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang["</2"](context.vars.elem, Type.integer(3));
          },
        },
      ],
      contextFixture(),
    );

    it("drops elements while predicate is true", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(3), Type.integer(4)]),
      );
    });

    it("returns entire list when first element fails predicate", () => {
      const list = Type.list([Type.integer(5), Type.integer(1)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(5), Type.integer(1)]),
      );
    });

    it("returns empty list when all elements pass predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("returns empty list for empty input", () => {
      const result = testedFun(lessThan3, Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a 1-arity function", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (_context) => Type.boolean(true),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(fun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", [
          fun,
          Type.list([Type.integer(1)]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(lessThan3, Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", [
          lessThan3,
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if function returns non-boolean", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (_context) => Type.integer(42),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => testedFun(badFun, Type.list([Type.integer(1)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile_2/4"),
      );
    });
  });

  describe("unzip/1", () => {
    const testedFun = Erlang_Lists["unzip/1"];

    it("unzips list of tuples", () => {
      const listOfTuples = Type.list([
        Type.tuple([Type.integer(1), Type.atom("a")]),
        Type.tuple([Type.integer(2), Type.atom("b")]),
        Type.tuple([Type.integer(3), Type.atom("c")]),
      ]);
      const result = testedFun(listOfTuples);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
        ]),
      );
    });

    it("unzips empty list", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.list([]), Type.list([])]),
      );
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([
              Type.tuple([Type.integer(1), Type.integer(2)]),
              Type.tuple([Type.integer(3), Type.integer(4)]),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip/1", [
          Type.improperList([
            Type.tuple([Type.integer(1), Type.integer(2)]),
            Type.tuple([Type.integer(3), Type.integer(4)]),
          ]),
        ]),
      );
    });

    it("raises FunctionClauseError if list contains non-2-tuple", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([
              Type.tuple([Type.integer(1), Type.integer(2)]),
              Type.tuple([Type.integer(3)]),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip_1/3"),
      );
    });
  });

  describe("usort/1", () => {
    const testedFun = Erlang_Lists["usort/1"];

    it("sorts and removes duplicates", () => {
      const list = Type.list([
        Type.integer(3),
        Type.integer(1),
        Type.integer(2),
        Type.integer(1),
        Type.integer(3),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("handles list with no duplicates", () => {
      const list = Type.list([Type.integer(3), Type.integer(1), Type.integer(2)]);
      const result = testedFun(list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("handles list with all duplicates", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(1),
        Type.integer(1),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort_1/4"),
      );
    });
  });

  describe("zip/2", () => {
    const testedFun = Erlang_Lists["zip/2"];

    it("zips two lists of same length", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const list2 = Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.integer(1), Type.atom("a")]),
          Type.tuple([Type.integer(2), Type.atom("b")]),
          Type.tuple([Type.integer(3), Type.atom("c")]),
        ]),
      );
    });

    it("zips empty lists", () => {
      const result = testedFun(Type.list([]), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/2", [
          Type.atom("abc"),
          Type.list([]),
        ]),
      );
    });

    it("raises FunctionClauseError if second argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.list([]), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/2", [
          Type.list([]),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if first list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([Type.integer(1), Type.integer(2)]),
            Type.list([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip_1/3"),
      );
    });

    it("raises FunctionClauseError if second list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip_1/3"),
      );
    });

    it("raises ErlangError if lists have different lengths", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1)]),
            Type.list([Type.integer(1), Type.integer(2)]),
          ),
        "ErlangError",
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    });
  });
});

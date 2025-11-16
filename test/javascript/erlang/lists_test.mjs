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

  describe("concat/1", () => {
    const testedFun = Erlang_Lists["concat/1"];

    it("concatenates atoms", () => {
      const list = Type.list([Type.atom("hello"), Type.atom("world")]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.atom("helloworld"));
    });

    it("concatenates mixed atoms and integers", () => {
      const list = Type.list([Type.atom("test"), Type.integer(123)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.atom("test123"));
    });

    it("handles empty list", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(result, Type.atom(""));
    });

    it("concatenates with floats", () => {
      const list = Type.list([Type.atom("pi"), Type.float(3.14)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.atom("pi3.14"));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([Type.atom("a"), Type.atom("b")]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [
          Type.improperList([Type.atom("a"), Type.atom("b")]),
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

  describe("droplast/1", () => {
    const testedFun = Erlang_Lists["droplast/1"];

    it("drops last element", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("returns empty list from single element list", () => {
      const list = Type.list([Type.integer(1)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if list is empty", () => {
      assertBoxedError(
        () => testedFun(Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [
          Type.list([]),
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

  describe("filtermap/2", () => {
    const testedFun = Erlang_Lists["filtermap/2"];

    const doubleIfEven = Type.anonymousFunction(
      1,
      [{
        params: (_context) => [Type.variablePattern("x")],
        guards: [],
        body: (context) => {
          const x = context.vars.x;
          const rem = Erlang["rem/2"](x, Type.integer(2));
          if (Interpreter.isEqual(rem, Type.integer(0))) {
            return Type.tuple([Type.atom("true"), Erlang["*/2"](x, Type.integer(2))]);
          }
          return Type.atom("false");
        },
      }],
      contextFixture(),
    );

    it("filters and maps elements", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3), Type.integer(4)]);
      const result = testedFun(doubleIfEven, list);
      assert.deepStrictEqual(result, Type.list([Type.integer(4), Type.integer(8)]));
    });

    it("handles true to keep element as-is", () => {
      const keepAll = Type.anonymousFunction(1, [{
        params: (_context) => [Type.variablePattern("x")],
        guards: [],
        body: (_context) => Type.atom("true"),
      }], contextFixture());

      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(keepAll, list);
      assert.deepStrictEqual(result, list);
    });

    it("handles false to filter out element", () => {
      const rejectAll = Type.anonymousFunction(1, [{
        params: (_context) => [Type.variablePattern("x")],
        guards: [],
        body: (_context) => Type.atom("false"),
      }], contextFixture());

      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(rejectAll, list);
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError for wrong arity", () => {
      const wrongArity = Type.anonymousFunction(2, [{
        params: (_context) => [Type.variablePattern("x"), Type.variablePattern("y")],
        guards: [],
        body: (_context) => Type.atom("true"),
      }], contextFixture());

      assertBoxedError(
        () => testedFun(wrongArity, Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap/2", [wrongArity, Type.list([])]),
      );
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

  describe("flatten/2", () => {
    const testedFun = Erlang_Lists["flatten/2"];

    it("flattens list and appends tail", () => {
      const list = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3)]),
      ]);
      const tail = Type.list([Type.integer(4), Type.integer(5)]);
      const result = testedFun(list, tail);

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

    it("handles non-list tail", () => {
      const list = Type.list([Type.list([Type.integer(1)])]);
      const result = testedFun(list, Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2)]),
      );
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/2", [
          Type.atom("abc"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("flatlength/1", () => {
    const testedFun = Erlang_Lists["flatlength/1"];

    it("counts elements in deeply nested list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.list([Type.integer(2), Type.integer(3)]),
        Type.list([Type.list([Type.integer(4)])]),
      ]);
      const result = testedFun(list);
      assert.deepStrictEqual(result, Type.integer(4));
    });

    it("returns 0 for empty list", () => {
      const result = testedFun(Type.list([]));
      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises FunctionClauseError for improper list", () => {
      const improperList = Type.improperList([
        Type.integer(1),
        Type.integer(2),
      ]);
      assertBoxedError(
        () => testedFun(improperList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatlength/1", [
          improperList,
        ]),
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

  describe("keydelete/3", () => {
    const testedFun = Erlang_Lists["keydelete/3"];

    it("deletes first tuple matching key at index", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
        Type.tuple([Type.atom("a"), Type.integer(3)]),
      ]);
      const result = testedFun(Type.atom("a"), Type.integer(1), tuples);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.atom("b"), Type.integer(2)]),
          Type.tuple([Type.atom("a"), Type.integer(3)]),
        ]),
      );
    });

    it("returns original list if no match found", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const result = testedFun(Type.atom("b"), Type.integer(1), tuples);

      assert.deepStrictEqual(result, tuples);
    });

    it("handles empty list", () => {
      const result = testedFun(Type.atom("a"), Type.integer(1), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises ArgumentError if index is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.atom("not_int"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if index is less than 1", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.integer(0), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if third argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.integer(1), Type.atom("not_list")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });

    it("raises ArgumentError if list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.atom("a"),
            Type.integer(1),
            Type.improperList([
              Type.tuple([Type.atom("a"), Type.integer(1)]),
              Type.tuple([Type.atom("b"), Type.integer(2)]),
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

  describe("keymap/3", () => {
    const testedFun = Erlang_Lists["keymap/3"];

    const double = Type.anonymousFunction(1, [{
      params: (_context) => [Type.variablePattern("x")],
      guards: [],
      body: (context) => Erlang["*/2"](context.vars.x, Type.integer(2)),
    }], contextFixture());

    it("maps function over key position in tuples", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
      ]);
      const result = testedFun(double, Type.integer(2), tuples);

      assert.deepStrictEqual(result, Type.list([
        Type.tuple([Type.atom("a"), Type.integer(2)]),
        Type.tuple([Type.atom("b"), Type.integer(4)]),
      ]));
    });

    it("raises ArgumentError if index not an integer", () => {
      assertBoxedError(
        () => testedFun(double, Type.atom("bad"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });
  });

  describe("keystore/4", () => {
    const testedFun = Erlang_Lists["keystore/4"];

    it("replaces tuple if key exists", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const newTuple = Type.tuple([Type.atom("a"), Type.integer(99)]);
      const result = testedFun(Type.atom("a"), Type.integer(1), tuples, newTuple);

      assert.deepStrictEqual(result, Type.list([newTuple]));
    });

    it("appends tuple if key doesn't exist", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const newTuple = Type.tuple([Type.atom("b"), Type.integer(2)]);
      const result = testedFun(Type.atom("b"), Type.integer(1), tuples, newTuple);

      assert.deepStrictEqual(result, Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        newTuple,
      ]));
    });

    it("raises ArgumentError if index not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.atom("bad"), Type.list([]), Type.tuple([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });
  });

  describe("keyreplace/4", () => {
    const testedFun = Erlang_Lists["keyreplace/4"];

    it("replaces first tuple matching key", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
      ]);
      const newTuple = Type.tuple([Type.atom("a"), Type.integer(99)]);
      const result = testedFun(Type.atom("a"), Type.integer(1), tuples, newTuple);

      assert.deepStrictEqual(
        result,
        Type.list([newTuple, Type.tuple([Type.atom("b"), Type.integer(2)])]),
      );
    });

    it("returns original list if no match", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const newTuple = Type.tuple([Type.atom("c"), Type.integer(3)]);
      const result = testedFun(Type.atom("b"), Type.integer(1), tuples, newTuple);

      assert.deepStrictEqual(result, tuples);
    });

    it("raises ArgumentError if index is not an integer", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.atom("a"),
            Type.atom("not_int"),
            Type.list([]),
            Type.tuple([]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });
  });

  describe("keysort/2", () => {
    const testedFun = Erlang_Lists["keysort/2"];

    it("sorts tuples by key at index", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("c"), Type.integer(3)]),
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
      ]);
      const result = testedFun(Type.integer(1), tuples);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.atom("a"), Type.integer(1)]),
          Type.tuple([Type.atom("b"), Type.integer(2)]),
          Type.tuple([Type.atom("c"), Type.integer(3)]),
        ]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(Type.integer(1), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises ArgumentError if index is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_int"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });
  });

  describe("keytake/3", () => {
    const testedFun = Erlang_Lists["keytake/3"];

    it("returns {value, Tuple, Rest} when match found", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
        Type.tuple([Type.atom("c"), Type.integer(3)]),
      ]);
      const result = testedFun(Type.atom("b"), Type.integer(1), tuples);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.atom("value"),
          Type.tuple([Type.atom("b"), Type.integer(2)]),
          Type.list([
            Type.tuple([Type.atom("a"), Type.integer(1)]),
            Type.tuple([Type.atom("c"), Type.integer(3)]),
          ]),
        ]),
      );
    });

    it("returns false when no match found", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const result = testedFun(Type.atom("b"), Type.integer(1), tuples);

      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("raises ArgumentError if index is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.atom("not_int"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });
  });

  describe("keymerge/3", () => {
    const testedFun = Erlang_Lists["keymerge/3"];

    it("merges two sorted tuple lists by key", () => {
      const tuples1 = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("c"), Type.integer(3)]),
      ]);
      const tuples2 = Type.list([
        Type.tuple([Type.atom("b"), Type.integer(2)]),
        Type.tuple([Type.atom("d"), Type.integer(4)]),
      ]);
      const result = testedFun(Type.integer(1), tuples1, tuples2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.atom("a"), Type.integer(1)]),
          Type.tuple([Type.atom("b"), Type.integer(2)]),
          Type.tuple([Type.atom("c"), Type.integer(3)]),
          Type.tuple([Type.atom("d"), Type.integer(4)]),
        ]),
      );
    });

    it("handles empty lists", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const result = testedFun(Type.integer(1), tuples, Type.list([]));
      assert.deepStrictEqual(result, tuples);
    });

    it("raises ArgumentError for invalid index", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), Type.list([]), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("join/2", () => {
    const testedFun = Erlang_Lists["join/2"];

    it("joins list elements with separator", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(Type.atom("sep"), list);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.atom("sep"),
          Type.integer(2),
          Type.atom("sep"),
          Type.integer(3),
        ]),
      );
    });

    it("returns empty list for empty input", () => {
      const result = testedFun(Type.atom("sep"), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("returns single element for single element list", () => {
      const result = testedFun(Type.atom("sep"), Type.list([Type.integer(1)]));

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
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

  describe("mapfoldl/3", () => {
    const testedFun = Erlang_Lists["mapfoldl/3"];

    const doubleAndSum = Type.anonymousFunction(2, [{
      params: (_context) => [Type.variablePattern("x"), Type.variablePattern("acc")],
      guards: [],
      body: (context) => {
        const doubled = Erlang["*/2"](context.vars.x, Type.integer(2));
        const newAcc = Erlang["+/2"](context.vars.acc, context.vars.x);
        return Type.tuple([doubled, newAcc]);
      },
    }], contextFixture());

    it("maps and folds from left", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(doubleAndSum, Type.integer(0), list);

      assert.deepStrictEqual(result, Type.tuple([
        Type.list([Type.integer(2), Type.integer(4), Type.integer(6)]),
        Type.integer(6),
      ]));
    });

    it("handles empty list", () => {
      const result = testedFun(doubleAndSum, Type.integer(0), Type.list([]));

      assert.deepStrictEqual(result, Type.tuple([Type.list([]), Type.integer(0)]));
    });
  });

  describe("mapfoldr/3", () => {
    const testedFun = Erlang_Lists["mapfoldr/3"];

    const doubleAndSum = Type.anonymousFunction(2, [{
      params: (_context) => [Type.variablePattern("x"), Type.variablePattern("acc")],
      guards: [],
      body: (context) => {
        const doubled = Erlang["*/2"](context.vars.x, Type.integer(2));
        const newAcc = Erlang["+/2"](context.vars.acc, context.vars.x);
        return Type.tuple([doubled, newAcc]);
      },
    }], contextFixture());

    it("maps and folds from right", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(doubleAndSum, Type.integer(0), list);

      assert.deepStrictEqual(result, Type.tuple([
        Type.list([Type.integer(2), Type.integer(4), Type.integer(6)]),
        Type.integer(6),
      ]));
    });

    it("handles empty list", () => {
      const result = testedFun(doubleAndSum, Type.integer(0), Type.list([]));

      assert.deepStrictEqual(result, Type.tuple([Type.list([]), Type.integer(0)]));
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

  describe("partition/2", () => {
    const testedFun = Erlang_Lists["partition/2"];

    const greaterThan2 = Type.anonymousFunction(
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

    it("partitions list based on predicate", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(3),
        Type.integer(2),
        Type.integer(4),
      ]);
      const result = testedFun(greaterThan2, list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(3), Type.integer(4)]),
          Type.list([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("returns all in first list if all satisfy", () => {
      const list = Type.list([Type.integer(3), Type.integer(4)]);
      const result = testedFun(greaterThan2, list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(3), Type.integer(4)]),
          Type.list([]),
        ]),
      );
    });

    it("returns all in second list if none satisfy", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(greaterThan2, list);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([]),
          Type.list([Type.integer(1), Type.integer(2)]),
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

  describe("merge/1", () => {
    const testedFun = Erlang_Lists["merge/1"];

    it("merges list of sorted lists", () => {
      const listOfLists = Type.list([
        Type.list([Type.integer(1), Type.integer(5)]),
        Type.list([Type.integer(2), Type.integer(6)]),
        Type.list([Type.integer(3), Type.integer(7)]),
      ]);
      const result = testedFun(listOfLists);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(5),
          Type.integer(6),
          Type.integer(7),
        ]),
      );
    });

    it("handles empty list of lists", () => {
      const result = testedFun(Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError for non-list argument", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/1", [
          Type.atom("abc"),
        ]),
      );
    });
  });

  describe("merge/2", () => {
    const testedFun = Erlang_Lists["merge/2"];

    it("merges two sorted lists", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(3), Type.integer(5)]);
      const list2 = Type.list([Type.integer(2), Type.integer(4), Type.integer(6)]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
          Type.integer(5),
          Type.integer(6),
        ]),
      );
    });

    it("handles empty lists", () => {
      const result = testedFun(Type.list([]), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/2", [
          Type.atom("not_list"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("merge3/3", () => {
    const testedFun = Erlang_Lists["merge3/3"];

    it("merges three sorted lists", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(4)]);
      const list2 = Type.list([Type.integer(2), Type.integer(5)]);
      const list3 = Type.list([Type.integer(3), Type.integer(6)]);
      const result = testedFun(list1, list2, list3);

      assert.deepStrictEqual(result, Type.list([
        Type.integer(1), Type.integer(2), Type.integer(3),
        Type.integer(4), Type.integer(5), Type.integer(6),
      ]));
    });

    it("handles empty lists", () => {
      const result = testedFun(Type.list([]), Type.list([]), Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });
  });

  describe("prefix/2", () => {
    const testedFun = Erlang_Lists["prefix/2"];

    it("returns true when first list is prefix of second", () => {
      const prefix = Type.list([Type.integer(1), Type.integer(2)]);
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(prefix, list);

      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("returns false when not a prefix", () => {
      const prefix = Type.list([Type.integer(1), Type.integer(3)]);
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(prefix, list);

      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("returns true for empty prefix", () => {
      const result = testedFun(Type.list([]), Type.list([Type.integer(1)]));

      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          Type.atom("not_list"),
          Type.list([]),
        ]),
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

  describe("search/2", () => {
    const testedFun = Erlang_Lists["search/2"];

    const greaterThan2 = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            const result = Erlang[">/2"](context.vars.elem, Type.integer(2));
            return Type.isTrue(result)
              ? Type.tuple([Type.atom("true"), context.vars.elem])
              : result;
          },
        },
      ],
      contextFixture(),
    );

    it("returns {value, Element} when predicate returns true", () => {
      const list = Type.list([Type.integer(1), Type.integer(3), Type.integer(2)]);
      const result = testedFun(greaterThan2, list);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.atom("value"), Type.integer(3)]),
      );
    });

    it("returns false if no element satisfies predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(greaterThan2, list);

      assert.deepStrictEqual(result, Type.boolean(false));
    });
  });

  describe("seq/2", () => {
    const testedFun = Erlang_Lists["seq/2"];

    it("generates sequence from 1 to 5", () => {
      const result = testedFun(Type.integer(1), Type.integer(5));

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

    it("handles single element sequence", () => {
      const result = testedFun(Type.integer(5), Type.integer(5));

      assert.deepStrictEqual(result, Type.list([Type.integer(5)]));
    });
  });

  describe("seq/3", () => {
    const testedFun = Erlang_Lists["seq/3"];

    it("generates sequence with step 2", () => {
      const result = testedFun(Type.integer(1), Type.integer(7), Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(3), Type.integer(5), Type.integer(7)]),
      );
    });

    it("handles negative step", () => {
      const result = testedFun(Type.integer(5), Type.integer(1), Type.integer(-1));

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(5),
          Type.integer(4),
          Type.integer(3),
          Type.integer(2),
          Type.integer(1),
        ]),
      );
    });

    it("raises ArgumentError if step is zero", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.integer(5), Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "zero"),
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

  describe("sort/2", () => {
    const testedFun = Erlang_Lists["sort/2"];

    const ascending = Type.anonymousFunction(2, [{
      params: (_context) => [Type.variablePattern("a"), Type.variablePattern("b")],
      guards: [],
      body: (context) => {
        const comp = Interpreter.compareTerms(context.vars.a, context.vars.b);
        return comp <= 0 ? Type.atom("true") : Type.atom("false");
      },
    }], contextFixture());

    it("sorts list with custom comparator", () => {
      const list = Type.list([Type.integer(3), Type.integer(1), Type.integer(2)]);
      const result = testedFun(ascending, list);

      assert.deepStrictEqual(result, Type.list([
        Type.integer(1), Type.integer(2), Type.integer(3),
      ]));
    });

    it("handles empty list", () => {
      const result = testedFun(ascending, Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
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

  describe("splitwith/2", () => {
    const testedFun = Erlang_Lists["splitwith/2"];

    const lessThan3 = Type.anonymousFunction(1, [{
      params: (_context) => [Type.variablePattern("x")],
      guards: [],
      body: (context) => Erlang["</2"](context.vars.x, Type.integer(3)),
    }], contextFixture());

    it("splits list at first failing predicate", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3), Type.integer(1)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(result, Type.tuple([
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3), Type.integer(1)]),
      ]));
    });

    it("handles all satisfying", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(lessThan3, list);

      assert.deepStrictEqual(result, Type.tuple([list, Type.list([])]));
    });
  });

  describe("sum/1", () => {
    const testedFun = Erlang_Lists["sum/1"];

    it("sums integers", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.integer(10));
    });

    it("sums floats", () => {
      const list = Type.list([Type.float(1.5), Type.float(2.5), Type.float(3.0)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(7.0));
    });

    it("sums mixed integers and floats", () => {
      const list = Type.list([Type.integer(1), Type.float(2.5), Type.integer(3)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.float(6.5));
    });

    it("sums empty list to zero", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArgumentError for non-numeric element", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1), Type.atom("abc"), Type.integer(3)]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list of numbers"),
      );
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sum/1", [
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if list is improper", () => {
      assertBoxedError(
        () => testedFun(Type.improperList([Type.integer(1), Type.integer(2)])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.sum/1", [
          Type.improperList([Type.integer(1), Type.integer(2)]),
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

  describe("subtract/2", () => {
    const testedFun = Erlang_Lists["subtract/2"];

    it("subtracts elements of second list from first", () => {
      const list1 = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(2),
      ]);
      const list2 = Type.list([Type.integer(2), Type.integer(4)]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(3), Type.integer(2)]),
      );
    });

    it("handles empty lists", () => {
      const result = testedFun(Type.list([]), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.subtract/2", [
          Type.atom("not_list"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("suffix/2", () => {
    const testedFun = Erlang_Lists["suffix/2"];

    it("returns true when first list is suffix of second", () => {
      const suffix = Type.list([Type.integer(2), Type.integer(3)]);
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(suffix, list);

      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("returns false when not a suffix", () => {
      const suffix = Type.list([Type.integer(1), Type.integer(3)]);
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(suffix, list);

      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("returns true for empty suffix", () => {
      const result = testedFun(Type.list([]), Type.list([Type.integer(1)]));

      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("raises FunctionClauseError if first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.suffix/2", [
          Type.atom("not_list"),
          Type.list([]),
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

  describe("unzip3/1", () => {
    const testedFun = Erlang_Lists["unzip3/1"];

    it("unzips list of 3-tuples into three lists", () => {
      const tuples = Type.list([
        Type.tuple([Type.integer(1), Type.atom("a"), Type.float(1.5)]),
        Type.tuple([Type.integer(2), Type.atom("b"), Type.float(2.5)]),
        Type.tuple([Type.integer(3), Type.atom("c"), Type.float(3.5)]),
      ]);
      const result = testedFun(tuples);

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
          Type.list([Type.float(1.5), Type.float(2.5), Type.float(3.5)]),
        ]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(Type.list([]));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.list([]), Type.list([]), Type.list([])]),
      );
    });

    it("raises FunctionClauseError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip3/1", [
          Type.atom("not_list"),
        ]),
      );
    });

    it("raises FunctionClauseError if list contains non-3-tuple", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([
              Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
              Type.tuple([Type.integer(4), Type.integer(5)]),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip3_1/4"),
      );
    });
  });

  describe("uniq/1", () => {
    const testedFun = Erlang_Lists["uniq/1"];

    it("removes consecutive duplicates", () => {
      const list = Type.list([
        Type.integer(1), Type.integer(1), Type.integer(2),
        Type.integer(3), Type.integer(3), Type.integer(3), Type.integer(2),
      ]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.list([
        Type.integer(1), Type.integer(2), Type.integer(3), Type.integer(2),
      ]));
    });

    it("handles list with no duplicates", () => {
      const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, list);
    });

    it("handles empty list", () => {
      const result = testedFun(Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });
  });

  describe("uniq/2", () => {
    const testedFun = Erlang_Lists["uniq/2"];

    const caselessEqual = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("a"),
            Type.variablePattern("b"),
          ],
          guards: [],
          body: (context) => {
            const a = context.vars.a;
            const b = context.vars.b;
            if (Type.isAtom(a) && Type.isAtom(b)) {
              return Type.boolean(
                a.value.toLowerCase() === b.value.toLowerCase(),
              );
            }
            return Interpreter.isEqual(a, b)
              ? Type.atom("true")
              : Type.atom("false");
          },
        },
      ],
      contextFixture(),
    );

    it("removes consecutive duplicates using custom equality", () => {
      const list = Type.list([
        Type.atom("a"),
        Type.atom("A"),
        Type.atom("b"),
        Type.atom("B"),
        Type.atom("b"),
      ]);
      const result = testedFun(caselessEqual, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.atom("a"), Type.atom("b")]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(caselessEqual, Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError for non-function first argument", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_fun"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq/2", [
          Type.atom("not_fun"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("ukeysort/2", () => {
    const testedFun = Erlang_Lists["ukeysort/2"];

    it("sorts tuples by key and removes duplicates", () => {
      const tuples = Type.list([
        Type.tuple([Type.atom("b"), Type.integer(2)]),
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("a"), Type.integer(3)]),
      ]);
      const result = testedFun(Type.integer(1), tuples);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.atom("a"), Type.integer(1)]),
          Type.tuple([Type.atom("b"), Type.integer(2)]),
        ]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(Type.integer(1), Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises ArgumentError for invalid index", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("ukeymerge/3", () => {
    const testedFun = Erlang_Lists["ukeymerge/3"];

    it("merges sorted tuple lists and removes duplicates by key", () => {
      const tuples1 = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("c"), Type.integer(3)]),
      ]);
      const tuples2 = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(2)]),
        Type.tuple([Type.atom("b"), Type.integer(4)]),
      ]);
      const result = testedFun(Type.integer(1), tuples1, tuples2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.atom("a"), Type.integer(1)]),
          Type.tuple([Type.atom("b"), Type.integer(4)]),
          Type.tuple([Type.atom("c"), Type.integer(3)]),
        ]),
      );
    });

    it("handles empty lists", () => {
      const tuples = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);
      const result = testedFun(Type.integer(1), tuples, Type.list([]));
      assert.deepStrictEqual(result, tuples);
    });

    it("raises ArgumentError for invalid index", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), Type.list([]), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("umerge/1", () => {
    const testedFun = Erlang_Lists["umerge/1"];

    it("merges list of sorted lists with union", () => {
      const listOfLists = Type.list([
        Type.list([Type.integer(1), Type.integer(3)]),
        Type.list([Type.integer(2), Type.integer(3)]),
        Type.list([Type.integer(3), Type.integer(4)]),
      ]);
      const result = testedFun(listOfLists);

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

    it("handles empty list of lists", () => {
      const result = testedFun(Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError for non-list argument", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/1", [
          Type.atom("abc"),
        ]),
      );
    });
  });

  describe("umerge/2", () => {
    const testedFun = Erlang_Lists["umerge/2"];

    it("merges two sorted lists with union", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(3), Type.integer(5)]);
      const list2 = Type.list([Type.integer(3), Type.integer(4), Type.integer(5)]);
      const result = testedFun(list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(1),
          Type.integer(3),
          Type.integer(4),
          Type.integer(5),
        ]),
      );
    });

    it("handles empty lists", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = testedFun(list, Type.list([]));
      assert.deepStrictEqual(result, list);
    });

    it("raises FunctionClauseError for non-list arguments", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/2", [
          Type.atom("abc"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("umerge3/3", () => {
    const testedFun = Erlang_Lists["umerge3/3"];

    it("merges three sorted lists with union", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(4)]);
      const list2 = Type.list([Type.integer(2), Type.integer(4)]);
      const list3 = Type.list([Type.integer(3), Type.integer(4)]);
      const result = testedFun(list1, list2, list3);

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

    it("handles empty lists", () => {
      const list = Type.list([Type.integer(1)]);
      const result = testedFun(list, Type.list([]), Type.list([]));
      assert.deepStrictEqual(result, list);
    });

    it("raises FunctionClauseError for non-list arguments", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.list([]), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3/3", [
          Type.atom("abc"),
          Type.list([]),
          Type.list([]),
        ]),
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

  describe("usort/2", () => {
    const testedFun = Erlang_Lists["usort/2"];

    const descending = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("a"),
            Type.variablePattern("b"),
          ],
          guards: [],
          body: (context) => {
            const comp = Interpreter.compareTerms(
              context.vars.a,
              context.vars.b,
            );
            return comp >= 0 ? Type.atom("true") : Type.atom("false");
          },
        },
      ],
      contextFixture(),
    );

    it("sorts with custom comparator and removes duplicates", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(3),
        Type.integer(2),
        Type.integer(3),
        Type.integer(1),
      ]);
      const result = testedFun(descending, list);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(3), Type.integer(2), Type.integer(1)]),
      );
    });

    it("handles empty list", () => {
      const result = testedFun(descending, Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError for non-function first argument", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_fun"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort/2", [
          Type.atom("not_fun"),
          Type.list([]),
        ]),
      );
    });
  });

  describe("zipwith/3", () => {
    const testedFun = Erlang_Lists["zipwith/3"];

    const add = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("a"),
            Type.variablePattern("b"),
          ],
          guards: [],
          body: (context) => {
            return Erlang["+/2"](context.vars.a, context.vars.b);
          },
        },
      ],
      contextFixture(),
    );

    it("combines two lists with a function", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
      const list2 = Type.list([Type.integer(10), Type.integer(20), Type.integer(30)]);
      const result = testedFun(add, list1, list2);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(11), Type.integer(22), Type.integer(33)]),
      );
    });

    it("handles empty lists", () => {
      const result = testedFun(add, Type.list([]), Type.list([]));

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if fun is not a function", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.atom("notfun"),
            Type.list([Type.integer(1)]),
            Type.list([Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          Type.atom("notfun"),
          Type.list([Type.integer(1)]),
          Type.list([Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if fun has wrong arity", () => {
      const wrongArity = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => context.vars.x,
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () =>
          testedFun(
            wrongArity,
            Type.list([Type.integer(1)]),
            Type.list([Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          wrongArity,
          Type.list([Type.integer(1)]),
          Type.list([Type.integer(2)]),
        ]),
      );
    });

    it("raises FunctionClauseError if first list argument is not a list", () => {
      assertBoxedError(
        () => testedFun(add, Type.atom("abc"), Type.list([])),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          add,
          Type.atom("abc"),
          Type.list([]),
        ]),
      );
    });

    it("raises FunctionClauseError if second list argument is not a list", () => {
      assertBoxedError(
        () => testedFun(add, Type.list([]), Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          add,
          Type.list([]),
          Type.atom("abc"),
        ]),
      );
    });

    it("raises FunctionClauseError if first list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            add,
            Type.improperList([Type.integer(1), Type.integer(2)]),
            Type.list([Type.integer(3), Type.integer(4)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith_1/4"),
      );
    });

    it("raises FunctionClauseError if second list is improper", () => {
      assertBoxedError(
        () =>
          testedFun(
            add,
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.improperList([Type.integer(3), Type.integer(4)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith_1/4"),
      );
    });

    it("raises ErlangError if lists have different lengths", () => {
      assertBoxedError(
        () =>
          testedFun(
            add,
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.list([Type.integer(3)]),
          ),
        "ErlangError",
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    });
  });

  describe("zip3/3", () => {
    const testedFun = Erlang_Lists["zip3/3"];

    it("zips three lists of same length", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(2)]);
      const list2 = Type.list([Type.atom("a"), Type.atom("b")]);
      const list3 = Type.list([Type.float(1.5), Type.float(2.5)]);
      const result = testedFun(list1, list2, list3);

      assert.deepStrictEqual(result, Type.list([
        Type.tuple([Type.integer(1), Type.atom("a"), Type.float(1.5)]),
        Type.tuple([Type.integer(2), Type.atom("b"), Type.float(2.5)]),
      ]));
    });

    it("handles empty lists", () => {
      const result = testedFun(Type.list([]), Type.list([]), Type.list([]));
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises ErlangError if lists have different lengths", () => {
      assertBoxedError(
        () => testedFun(
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([Type.integer(3)]),
          Type.list([Type.integer(4)]),
        ),
        "ErlangError",
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    });
  });

  describe("zipwith3/4", () => {
    const testedFun = Erlang_Lists["zipwith3/4"];

    const sumThree = Type.anonymousFunction(
      3,
      [
        {
          params: (_context) => [
            Type.variablePattern("a"),
            Type.variablePattern("b"),
            Type.variablePattern("c"),
          ],
          guards: [],
          body: (context) => {
            const sum1 = Erlang["+/2"](context.vars.a, context.vars.b);
            return Erlang["+/2"](sum1, context.vars.c);
          },
        },
      ],
      contextFixture(),
    );

    it("combines three lists with a function", () => {
      const list1 = Type.list([Type.integer(1), Type.integer(2)]);
      const list2 = Type.list([Type.integer(10), Type.integer(20)]);
      const list3 = Type.list([Type.integer(100), Type.integer(200)]);
      const result = testedFun(sumThree, list1, list2, list3);

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(111), Type.integer(222)]),
      );
    });

    it("handles empty lists", () => {
      const result = testedFun(
        sumThree,
        Type.list([]),
        Type.list([]),
        Type.list([]),
      );

      assert.deepStrictEqual(result, Type.list([]));
    });

    it("raises FunctionClauseError if fun has wrong arity", () => {
      const wrongArity = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (context) => Erlang["+/2"](context.vars.a, context.vars.b),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () =>
          testedFun(
            wrongArity,
            Type.list([Type.integer(1)]),
            Type.list([Type.integer(2)]),
            Type.list([Type.integer(3)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/4", [
          wrongArity,
          Type.list([Type.integer(1)]),
          Type.list([Type.integer(2)]),
          Type.list([Type.integer(3)]),
        ]),
      );
    });

    it("raises ErlangError if lists have different lengths", () => {
      assertBoxedError(
        () =>
          testedFun(
            sumThree,
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.list([Type.integer(3)]),
            Type.list([Type.integer(4)]),
          ),
        "ErlangError",
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
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

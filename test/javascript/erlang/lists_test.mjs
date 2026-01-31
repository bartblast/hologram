"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomA = Type.atom("a");
const atomAbc = Type.atom("abc");
const atomB = Type.atom("b");
const atomC = Type.atom("c");
const atomD = Type.atom("d");
const atomE = Type.atom("e");
const atomF = Type.atom("f");
const atomG = Type.atom("g");
const atomH = Type.atom("h");
const atomI = Type.atom("i");
const atomX = Type.atom("x");

const emptyList = Type.list();
const float2 = Type.float(2.0);
const float3 = Type.float(3.0);

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

const improperList = Type.improperList([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

const integer0 = Type.integer(0);
const integer1 = Type.integer(1);
const integer2 = Type.integer(2);
const integer3 = Type.integer(3);
const integer4 = Type.integer(4);
const integer5 = Type.integer(5);

const properList = Type.list([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

const list1 = Type.list([Type.integer(1)]);
const list2 = Type.list([Type.integer(1), Type.integer(2)]);
const list3 = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

const tupleX = Type.tuple([atomX]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/lists_test.exs
// Always update both together.

describe("Erlang_Lists", () => {
  describe("any/2", () => {
    const any = Erlang_Lists["any/2"];

    it("returns true if the first item in the list results in true", () => {
      const list = Type.list([
        Type.integer(3),
        Type.integer(1),
        Type.integer(2),
        Type.integer(0),
      ]);

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
      const result = any(fun, list);

      assertBoxedTrue(result);
    });

    it("returns true if the middle item in the list results in true", () => {
      const list = Type.list([
        Type.integer(0),
        Type.integer(1),
        Type.integer(3),
        Type.integer(2),
        Type.integer(0),
      ]);

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
      const result = any(fun, list);

      assertBoxedTrue(result);
    });

    it("returns true if the last item in the list results in true", () => {
      const list = Type.list([
        Type.integer(0),
        Type.integer(1),
        Type.integer(0),
        Type.integer(2),
        Type.integer(3),
      ]);

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
      const result = any(fun, list);

      assertBoxedTrue(result);
    });

    it("returns false if none of the items results in true when supplied to the anonymous function", () => {
      const list = Type.list([
        Type.integer(0),
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("elem")],
            guards: [],
            body: (context) => {
              return Erlang[">/2"](context.vars.elem, Type.integer(5));
            },
          },
        ],
        contextFixture(),
      );
      const result = any(fun, list);

      assertBoxedFalse(result);
    });

    it("returns false for empty list", () => {
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
      const result = any(fun, emptyList);

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if the first arg is not an anonymous function", () => {
      assertBoxedError(
        () => any(Type.atom("abc"), properList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":lists.any/2",
          Type.atom("abc"),
          properList,
        ),
      );
    });

    it("raises FunctionClauseError if the first arg is an anonymous function with arity different than 1", () => {
      const anonymousCompareFn = Type.anonymousFunction(
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

      assertBoxedError(
        () => any(funArity2, properList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":lists.any/2",
          anonymousCompareFn,
          properList,
        ),
      );
    });

    it("raises CaseClauseError if the second argument is not a list", () => {
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

      assertBoxedError(
        () => any(fun, Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    it("raises FunctionClauseError if the second argument is an improper list", () => {
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

      assertBoxedError(
        () => any(fun, improperList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", [improperList]),
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

  describe("flatmap/2", () => {
    const flatmap = Erlang_Lists["flatmap/2"];

    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("x")],
          guards: [],
          body: (context) => {
            return Type.list([
              context.vars.x,
              Erlang["*/2"](context.vars.x, Type.integer(10)),
            ]);
          },
        },
      ],
      contextFixture(),
    );

    it("returns empty list when given empty list", () => {
      const result = flatmap(fun, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("works with single element list", () => {
      const list = Type.list([integer1]);
      const result = flatmap(fun, list);
      const expected = Type.list([integer1, Type.integer(10)]);

      assert.deepStrictEqual(result, expected);
    });

    it("works with multiple element list", () => {
      const list = Type.list([integer1, integer2, integer3]);
      const result = flatmap(fun, list);

      const expected = Type.list([
        integer1,
        Type.integer(10),
        integer2,
        Type.integer(20),
        integer3,
        Type.integer(30),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns empty list when mapper returns empty lists", () => {
      const emptyFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.matchPlaceholder()],
            guards: [],
            body: (_context) => {
              return emptyList;
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([integer1, integer2, integer3]);
      const result = flatmap(emptyFun, list);

      assert.deepStrictEqual(result, emptyList);
    });

    it("flattens only one level", () => {
      const nestedFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return Type.list([Type.list([Type.list([context.vars.x])])]);
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([integer1, integer2]);
      const result = flatmap(nestedFun, list);

      const expected = Type.list([
        Type.list([Type.list([integer1])]),
        Type.list([Type.list([integer2])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatmap/2",
        [atomAbc, emptyList],
      );

      assertBoxedError(
        () => flatmap(atomAbc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 1", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatmap/2",
        [funArity2, emptyList],
      );

      assertBoxedError(
        () => flatmap(funArity2, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatmap_1/2",
        [fun, atomAbc],
      );

      assertBoxedError(
        () => flatmap(fun, atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is an improper list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatmap_1/2",
        [fun, integer3],
      );

      assertBoxedError(
        () => flatmap(fun, improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises ArgumentError if the mapper does not return a proper list", () => {
      const badFun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return Erlang["*/2"](context.vars.x, Type.integer(10));
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([integer1, integer2, integer3]);

      assertBoxedError(
        () => flatmap(badFun, list),
        "ArgumentError",
        "argument error",
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
    const flatten = Erlang_Lists["flatten/2"];

    it("empty list and empty tail", () => {
      const result = flatten(emptyList, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("empty list and non-empty tail", () => {
      const tail = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = flatten(emptyList, tail);

      assert.deepStrictEqual(result, tail);
    });

    it("non-nested list and empty tail", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = flatten(list, emptyList);

      assert.deepStrictEqual(result, list);
    });

    it("non-nested list and non-empty tail", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const tail = Type.list([
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
      ]);

      const result = flatten(list, tail);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("nested list and non-empty tail", () => {
      const list = Type.list([
        Type.integer(1),
        Type.list([
          Type.integer(2),
          Type.list([Type.integer(3), Type.integer(4)]),
        ]),
      ]);

      const tail = Type.list([Type.integer(5), Type.integer(6)]);

      const result = flatten(list, tail);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("deeply nested empty lists", () => {
      const list = Type.list([emptyList, Type.list([emptyList])]);
      const tail = Type.list([Type.integer(1), Type.integer(2)]);

      const result = flatten(list, tail);
      const expected = Type.list([Type.integer(1), Type.integer(2)]);

      assert.deepStrictEqual(result, expected);
    });

    it("improper tail", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);

      const tail = Type.improperList([
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
      ]);

      const result = flatten(list, tail);

      const expected = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not a list", () => {
      const list = Type.atom("abc");
      const tail = Type.list([Type.integer(1), Type.integer(2)]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/2",
        [list, tail],
      );

      assertBoxedError(
        () => flatten(list, tail),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the first argument is an improper list", () => {
      const list = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const tail = Type.list([Type.integer(4), Type.integer(5)]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/2",
        [list, tail],
      );

      assertBoxedError(
        () => flatten(list, tail),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the first argument contains a nested improper list", () => {
      const nestedImproperList = Type.improperList([
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      const list = Type.list([Type.integer(1), nestedImproperList]);
      const tail = Type.list([Type.integer(5), Type.integer(6)]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/1",
        [nestedImproperList],
      );

      assertBoxedError(
        () => flatten(list, tail),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is not a list", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const tail = Type.atom("abc");

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.flatten/2",
        [list, tail],
      );

      assertBoxedError(
        () => flatten(list, tail),
        "FunctionClauseError",
        expectedMessage,
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
            return Type.list([context.vars.elem, ...context.vars.acc.data]);
          },
        },
      ],
      contextFixture(),
    );

    const acc = Type.list();

    it("reduces empty list", () => {
      const result = foldl(fun, acc, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("reduces non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = foldl(fun, acc, list);

      const expected = Type.list([
        Type.integer(3),
        Type.integer(2),
        Type.integer(1),
      ]);

      assert.deepStrictEqual(result, expected);
    });

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

    // Client-side error message is intentionally simplified.
    it("raises FunctionClauseError if the third argument is an improper list", () => {
      const list = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assertBoxedError(
        () => foldl(fun, acc, list),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldl_1/3"),
      );
    });
  });

  describe("foldr/3", () => {
    const foldr = Erlang_Lists["foldr/3"];

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
            return Type.list([context.vars.elem, ...context.vars.acc.data]);
          },
        },
      ],
      contextFixture(),
    );

    const acc = Type.list();

    it("reduces empty list", () => {
      const result = foldr(fun, acc, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("reduces non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = foldr(fun, acc, list);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.foldr/3",
        [Type.atom("abc"), acc, emptyList],
      );

      assertBoxedError(
        () => foldr(Type.atom("abc"), acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

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
        ":lists.foldr/3",
        [fun, acc, emptyList],
      );

      assertBoxedError(
        () => foldr(fun, acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client-side error message is intentionally simplified.
    it("raises FunctionClauseError if the third argument is not a list", () => {
      assertBoxedError(
        () => foldr(fun, acc, Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr_1/3"),
      );
    });

    // Client-side error message is intentionally simplified.
    it("raises FunctionClauseError if the third argument is an improper list", () => {
      const improperList = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assertBoxedError(
        () => foldr(fun, acc, improperList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr_1/3"),
      );
    });
  });

  describe("keydelete/3", () => {
    const keydelete = Erlang_Lists["keydelete/3"];

    it("returns the original list if tuples list is empty", () => {
      const result = keydelete(atomC, integer1, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("single tuple, no match", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keydelete(atomC, integer1, tuples);

      assert.deepStrictEqual(result, tuples);
    });

    it("single tuple, match at first index", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keydelete(atomA, integer1, tuples);

      assert.deepStrictEqual(result, emptyList);
    });

    it("single tuple, match at middle index", () => {
      const tuples = Type.list([Type.tuple([integer1, atomB, float3])]);
      const result = keydelete(atomB, integer2, tuples);

      assert.deepStrictEqual(result, emptyList);
    });

    it("single tuple, match at last index", () => {
      const tuples = Type.list([Type.tuple([integer1, float2, atomC])]);
      const result = keydelete(atomC, integer3, tuples);

      assert.deepStrictEqual(result, emptyList);
    });

    it("multiple tuples, no match", () => {
      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        Type.tuple([atomD, atomE, atomF]),
        Type.tuple([atomG, atomH, atomI]),
      ]);

      const result = keydelete(atomC, integer1, tuples);

      assert.deepStrictEqual(result, tuples);
    });

    it("multiple tuples, match first tuple", () => {
      const tuple2 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        tuple2,
        tuple3,
      ]);

      const result = keydelete(atomA, integer1, tuples);
      const expected = Type.list([tuple2, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match middle tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        Type.tuple([atomA, integer2, float3]),
        tuple3,
      ]);

      const result = keydelete(atomA, integer1, tuples);
      const expected = Type.list([tuple1, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match last tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple2 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        tuple2,
        Type.tuple([atomA, integer2, float3]),
      ]);

      const result = keydelete(atomA, integer1, tuples);
      const expected = Type.list([tuple1, tuple2]);

      assert.deepStrictEqual(result, expected);
    });

    it("applies non-strict comparison", () => {
      const tuples = Type.list([Type.tuple([float2])]);
      const result = keydelete(integer2, integer1, tuples);

      assert.deepStrictEqual(result, emptyList);
    });

    it("raises FunctionClauseError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keydelete(atomA, float2, Type.list()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keydelete/3", [
          atomA,
          float2,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keydelete(atomA, integer0, Type.list()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keydelete/3", [
          atomA,
          integer0,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is not a list", () => {
      const tuples = Type.tuple([Type.tuple([atomB]), Type.tuple([atomC])]);

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keydelete3/3",
        [atomA, integer1, tuples],
      );

      assertBoxedError(
        () => keydelete(atomA, integer1, tuples),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is an improper list", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keydelete3/3",
        [atomA, integer1, Type.tuple([atomD])],
      );

      const tuples = Type.improperList([
        Type.tuple([atomB]),
        Type.tuple([atomC]),
        Type.tuple([atomD]),
      ]);

      assertBoxedError(
        () => keydelete(atomA, integer1, tuples),
        "FunctionClauseError",
        expectedMsg,
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

  describe("keyreplace/4", () => {
    const keyreplace = Erlang_Lists["keyreplace/4"];

    it("returns the original list if tuples list is empty", () => {
      const result = keyreplace(atomC, integer1, emptyList, tupleX);

      assert.deepStrictEqual(result, emptyList);
    });

    it("single tuple, no match", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keyreplace(atomC, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, tuples);
    });

    it("single tuple, match at first index", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keyreplace(atomA, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("single tuple, match at middle index", () => {
      const tuples = Type.list([Type.tuple([integer1, atomB, float3])]);
      const result = keyreplace(atomB, integer2, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("single tuple, match at last index", () => {
      const tuples = Type.list([Type.tuple([integer1, float2, atomC])]);
      const result = keyreplace(atomC, integer3, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("multiple tuples, no match", () => {
      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        Type.tuple([atomD, atomE, atomF]),
        Type.tuple([atomG, atomH, atomI]),
      ]);

      const result = keyreplace(atomC, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, tuples);
    });

    it("multiple tuples, match first tuple", () => {
      const tuple2 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        tuple2,
        tuple3,
      ]);

      const result = keyreplace(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tupleX, tuple2, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match middle tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        Type.tuple([atomA, integer2, float3]),
        tuple3,
      ]);

      const result = keyreplace(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tuple1, tupleX, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match last tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple2 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        tuple2,
        Type.tuple([atomA, integer2, float3]),
      ]);

      const result = keyreplace(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tuple1, tuple2, tupleX]);

      assert.deepStrictEqual(result, expected);
    });

    it("applies non-strict comparison", () => {
      const tuples = Type.list([Type.tuple([float2])]);
      const result = keyreplace(integer2, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("raises FunctionClauseError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keyreplace(atomA, float2, Type.list(), Type.tuple()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keyreplace/4", [
          atomA,
          float2,
          Type.list(),
          Type.tuple(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keyreplace(atomA, integer0, Type.list(), Type.tuple()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keyreplace/4", [
          atomA,
          integer0,
          Type.list(),
          Type.tuple(),
        ]),
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is not a list", () => {
      const tuples = Type.tuple([Type.tuple([atomB]), Type.tuple([atomC])]);

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keyreplace3/4",
        [atomA, integer1, tuples, Type.tuple()],
      );

      assertBoxedError(
        () => keyreplace(atomA, integer1, tuples, Type.tuple()),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is an improper list", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keyreplace3/4",
        [atomA, integer1, Type.tuple([atomD]), Type.tuple()],
      );

      const tuples = Type.improperList([
        Type.tuple([atomB]),
        Type.tuple([atomC]),
        Type.tuple([atomD]),
      ]);

      assertBoxedError(
        () => keyreplace(atomA, integer1, tuples, Type.tuple()),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the fourth argument (newTuple) is not a tuple", () => {
      assertBoxedError(
        () => keyreplace(atomA, integer1, Type.list(), atomX),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keyreplace/4", [
          atomA,
          integer1,
          Type.list(),
          atomX,
        ]),
      );
    });
  });

  describe("keysort/2", () => {
    const keysort = Erlang_Lists["keysort/2"];

    it("returns the empty list if the input is the empty list", () => {
      const result = keysort(Type.integer(3), emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("returns the unchanged one-element list", () => {
      const input = Type.list([Type.tuple([Type.atom("a"), Type.integer(2)])]);
      const result = keysort(Type.integer(1), input);

      assert.deepStrictEqual(result, input);
    });

    it("returns the unchanged one-element list even if the index is out of range of the tuple", () => {
      const input = Type.list([Type.tuple([Type.atom("a")])]);
      const result = keysort(Type.integer(3), input);

      assert.deepStrictEqual(result, input);
    });

    it("returns the unchanged one-element list even if the element is not a tuple", () => {
      const input = Type.list([Type.atom("a")]);
      const result = keysort(Type.integer(3), input);

      assert.deepStrictEqual(result, input);
    });

    it("sorts the list by the first element of each tuple", () => {
      const tuple1 = Type.tuple([Type.atom("b"), Type.integer(1)]);
      const tuple2 = Type.tuple([Type.atom("a"), Type.integer(2)]);
      const result = keysort(Type.integer(1), Type.list([tuple1, tuple2]));
      const expected = Type.list([tuple2, tuple1]);

      assert.deepStrictEqual(result, expected);
    });

    it("sorts the list by the middle element of each tuple", () => {
      const tuple1 = Type.tuple([
        Type.atom("a"),
        Type.integer(2),
        Type.atom("c"),
      ]);

      const tuple2 = Type.tuple([
        Type.atom("b"),
        Type.integer(1),
        Type.atom("d"),
      ]);

      const result = keysort(Type.integer(2), Type.list([tuple1, tuple2]));
      const expected = Type.list([tuple2, tuple1]);

      assert.deepStrictEqual(result, expected);
    });

    it("sorts the list by the last element of each tuple", () => {
      const tuple1 = Type.tuple([Type.atom("a"), Type.integer(2)]);
      const tuple2 = Type.tuple([Type.atom("b"), Type.integer(1)]);
      const result = keysort(Type.integer(2), Type.list([tuple1, tuple2]));
      const expected = Type.list([tuple2, tuple1]);

      assert.deepStrictEqual(result, expected);
    });

    it("is stable (preserves order of elements)", () => {
      const tuple1 = Type.tuple([Type.integer(1), Type.atom("a")]);
      const tuple2 = Type.tuple([Type.integer(1), Type.atom("b")]);
      const tuple3 = Type.tuple([Type.integer(1), Type.atom("c")]);
      const tuple4 = Type.tuple([Type.integer(1), Type.atom("d")]);
      const tuple5 = Type.tuple([Type.integer(2), Type.atom("e")]);
      const tuple6 = Type.tuple([Type.integer(3), Type.atom("f")]);
      const tuple7 = Type.tuple([Type.integer(3), Type.atom("g")]);
      const tuple8 = Type.tuple([Type.integer(4), Type.atom("h")]);

      const tuples = Type.list([
        tuple8,
        tuple1,
        tuple2,
        tuple6,
        tuple7,
        tuple3,
        tuple4,
        tuple5,
      ]);

      const result = keysort(Type.integer(1), tuples);

      const expected = Type.list([
        tuple1,
        tuple2,
        tuple3,
        tuple4,
        tuple5,
        tuple6,
        tuple7,
        tuple8,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an integer", () => {
      assertBoxedError(
        () => keysort(Type.float(1.0), emptyList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [
          Type.float(1.0),
          emptyList,
        ]),
      );
    });

    it("raises FunctionClauseError if the first argument is zero integer", () => {
      assertBoxedError(
        () => keysort(Type.integer(0), emptyList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [
          Type.integer(0),
          emptyList,
        ]),
      );
    });

    it("raises FunctionClauseError if the first argument is a negative integer", () => {
      assertBoxedError(
        () => keysort(Type.integer(-1), emptyList),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [
          Type.integer(-1),
          emptyList,
        ]),
      );
    });

    it("raises CaseClauseError if the second argument is not a list", () => {
      assertBoxedError(
        () => keysort(Type.integer(1), Type.atom("a")),
        "CaseClauseError",
        "no case clause matching: :a",
      );
    });

    it("raises CaseClauseError if the second argument is a two-element improper list", () => {
      assertBoxedError(
        () =>
          keysort(
            Type.integer(1),
            Type.improperList([Type.integer(1), Type.integer(2)]),
          ),
        "CaseClauseError",
        "no case clause matching: [1 | 2]",
      );
    });

    // Client-side error message is intentionally simplified.
    it("raises FunctionClauseError if the second argument is a larger improper list of tuples", () => {
      const index = Type.integer(1);

      const input = Type.improperList([
        Type.tuple([Type.atom("a")]),
        Type.tuple([Type.atom("b")]),
        Type.tuple([Type.atom("c")]),
      ]);

      assertBoxedError(
        () => keysort(index, input),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysplit_1/8"),
      );
    });

    it("raises ArgumentError if the second argument is a larger improper list of non tuples", () => {
      assertBoxedError(
        () => keysort(Type.integer(1), improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if an element of the list is not a tuple", () => {
      const input = Type.list([Type.tuple([Type.atom("a")]), Type.atom("b")]);

      assertBoxedError(
        () => keysort(Type.integer(1), input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if the index is out of range for any tuple in the list", () => {
      const input = Type.list([Type.tuple([Type.atom("a")]), Type.tuple()]);

      assertBoxedError(
        () => keysort(Type.integer(1), input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("keystore/4", () => {
    const keystore = Erlang_Lists["keystore/4"];

    it("appends the new tuple if tuples list is empty", () => {
      const result = keystore(atomC, integer1, emptyList, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("single tuple, no match", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keystore(atomC, integer1, tuples, tupleX);

      const expected = Type.list([
        Type.tuple([atomA, integer2, float3]),
        tupleX,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("single tuple, match at first index", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keystore(atomA, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("single tuple, match at middle index", () => {
      const tuples = Type.list([Type.tuple([integer1, atomB, float3])]);
      const result = keystore(atomB, integer2, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("single tuple, match at last index", () => {
      const tuples = Type.list([Type.tuple([integer1, float2, atomC])]);
      const result = keystore(atomC, integer3, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("multiple tuples, no match", () => {
      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        Type.tuple([atomD, atomE, atomF]),
        Type.tuple([atomG, atomH, atomI]),
      ]);

      const result = keystore(atomC, integer1, tuples, tupleX);

      const expected = Type.list([
        Type.tuple([atomA, integer2, float3]),
        Type.tuple([atomD, atomE, atomF]),
        Type.tuple([atomG, atomH, atomI]),
        tupleX,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match first tuple", () => {
      const tuple2 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        tuple2,
        tuple3,
      ]);

      const result = keystore(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tupleX, tuple2, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match middle tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        Type.tuple([atomA, integer2, float3]),
        tuple3,
      ]);

      const result = keystore(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tuple1, tupleX, tuple3]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match last tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple2 = Type.tuple([atomG, atomH, atomI]);

      const tuples = Type.list([
        tuple1,
        tuple2,
        Type.tuple([atomA, integer2, float3]),
      ]);

      const result = keystore(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tuple1, tuple2, tupleX]);

      assert.deepStrictEqual(result, expected);
    });

    it("skips tuple when its size is smaller than the index", () => {
      const tuples = Type.list([
        Type.tuple([atomA]),
        Type.tuple([atomB, atomA, atomC]),
      ]);

      const result = keystore(atomA, integer2, tuples, tupleX);
      const expected = Type.list([Type.tuple([atomA]), tupleX]);

      assert.deepStrictEqual(result, expected);
    });

    it("replaces only the first matching tuple", () => {
      const tuples = Type.list([
        Type.tuple([atomA, integer1]),
        Type.tuple([atomA, integer2]),
      ]);

      const result = keystore(atomA, integer1, tuples, tupleX);
      const expected = Type.list([tupleX, Type.tuple([atomA, integer2])]);

      assert.deepStrictEqual(result, expected);
    });

    it("applies non-strict comparison", () => {
      const tuples = Type.list([Type.tuple([float2])]);
      const result = keystore(integer2, integer1, tuples, tupleX);

      assert.deepStrictEqual(result, Type.list([tupleX]));
    });

    it("raises FunctionClauseError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keystore(atomA, float2, Type.list(), Type.tuple()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keystore/4", [
          atomA,
          float2,
          Type.list(),
          Type.tuple(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keystore(atomA, integer0, Type.list(), Type.tuple()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keystore/4", [
          atomA,
          integer0,
          Type.list(),
          Type.tuple(),
        ]),
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is not a list", () => {
      const tuples = Type.tuple([Type.tuple([atomB]), Type.tuple([atomC])]);

      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keystore2/4",
        [atomA, integer1, tuples, Type.tuple()],
      );

      assertBoxedError(
        () => keystore(atomA, integer1, tuples, Type.tuple()),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is an improper list", () => {
      const expectedMsg = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.keystore2/4",
        [atomA, integer1, Type.tuple([atomD]), Type.tuple()],
      );

      const tuples = Type.improperList([
        Type.tuple([atomB]),
        Type.tuple([atomC]),
        Type.tuple([atomD]),
      ]);

      assertBoxedError(
        () => keystore(atomA, integer1, tuples, Type.tuple()),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the fourth argument (newTuple) is not a tuple", () => {
      assertBoxedError(
        () => keystore(atomA, integer1, Type.list(), atomX),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keystore/4", [
          atomA,
          integer1,
          Type.list(),
          atomX,
        ]),
      );
    });
  });

  describe("keytake/3", () => {
    const keytake = Erlang_Lists["keytake/3"];

    it("returns false if tuples list is empty", () => {
      const result = keytake(atomC, integer1, emptyList);

      assertBoxedFalse(result);
    });

    it("single tuple, no match", () => {
      const tuples = Type.list([Type.tuple([atomA, integer2, float3])]);
      const result = keytake(atomC, integer1, tuples);

      assertBoxedFalse(result);
    });

    it("single tuple, match at first index", () => {
      const tuple = Type.tuple([atomA, integer2, float3]);
      const tuples = Type.list([tuple]);

      const result = keytake(atomA, integer1, tuples);
      const expected = Type.tuple([Type.atom("value"), tuple, emptyList]);

      assert.deepStrictEqual(result, expected);
    });

    it("single tuple, match at middle index", () => {
      const tuple = Type.tuple([integer1, atomB, float3]);
      const tuples = Type.list([tuple]);

      const result = keytake(atomB, integer2, tuples);
      const expected = Type.tuple([Type.atom("value"), tuple, emptyList]);

      assert.deepStrictEqual(result, expected);
    });

    it("single tuple, match at last index", () => {
      const tuple = Type.tuple([integer1, float2, atomC]);
      const tuples = Type.list([tuple]);

      const result = keytake(atomC, integer3, tuples);
      const expected = Type.tuple([Type.atom("value"), tuple, emptyList]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, no match", () => {
      const tuples = Type.list([
        Type.tuple([atomA, integer2, float3]),
        Type.tuple([atomD, atomE, atomF]),
        Type.tuple([atomG, atomH, atomI]),
      ]);

      const result = keytake(atomC, integer1, tuples);

      assertBoxedFalse(result);
    });

    it("multiple tuples, match first tuple", () => {
      const tuple1 = Type.tuple([atomA, integer2, float3]);
      const tuple2 = Type.tuple([atomD, atomE, atomF]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);
      const tuples = Type.list([tuple1, tuple2, tuple3]);

      const result = keytake(atomA, integer1, tuples);

      const expected = Type.tuple([
        Type.atom("value"),
        tuple1,
        Type.list([tuple2, tuple3]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match middle tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple2 = Type.tuple([atomA, integer2, float3]);
      const tuple3 = Type.tuple([atomG, atomH, atomI]);
      const tuples = Type.list([tuple1, tuple2, tuple3]);

      const result = keytake(atomA, integer1, tuples);

      const expected = Type.tuple([
        Type.atom("value"),
        tuple2,
        Type.list([tuple1, tuple3]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("multiple tuples, match last tuple", () => {
      const tuple1 = Type.tuple([atomD, atomE, atomF]);
      const tuple2 = Type.tuple([atomG, atomH, atomI]);
      const tuple3 = Type.tuple([atomA, integer2, float3]);
      const tuples = Type.list([tuple1, tuple2, tuple3]);

      const result = keytake(atomA, integer1, tuples);

      const expected = Type.tuple([
        Type.atom("value"),
        tuple3,
        Type.list([tuple1, tuple2]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("skips tuple when its size is smaller than the index", () => {
      const tuple1 = Type.tuple([atomA]);
      const tuple2 = Type.tuple([atomB, atomA, atomC]);
      const tuples = Type.list([tuple1, tuple2]);

      const result = keytake(atomA, integer2, tuples);

      const expected = Type.tuple([
        Type.atom("value"),
        tuple2,
        Type.list([tuple1]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns only the first matching tuple", () => {
      const tuple1 = Type.tuple([atomA, integer1]);
      const tuple2 = Type.tuple([atomA, integer2]);
      const tuples = Type.list([tuple1, tuple2]);

      const result = keytake(atomA, integer1, tuples);

      const expected = Type.tuple([
        Type.atom("value"),
        tuple1,
        Type.list([tuple2]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("applies non-strict comparison", () => {
      const tuple = Type.tuple([float2]);
      const tuples = Type.list([tuple]);

      const result = keytake(integer2, integer1, tuples);
      const expected = Type.tuple([Type.atom("value"), tuple, emptyList]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keytake(atomA, float2, Type.list()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keytake/3", [
          atomA,
          float2,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keytake(atomA, integer0, Type.list()),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.keytake/3", [
          atomA,
          integer0,
          Type.list(),
        ]),
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is not a list", () => {
      // Client-side error message is intentionally simplified.
      const expectedMsg =
        Interpreter.buildFunctionClauseErrorMsg(":lists.keytake/4");

      const tuples = Type.tuple([Type.tuple([atomB]), Type.tuple([atomC])]);

      assertBoxedError(
        () => keytake(atomA, integer1, tuples),
        "FunctionClauseError",
        expectedMsg,
      );
    });

    it("raises FunctionClauseError if the third argument (tuples) is an improper list", () => {
      // Client-side error message is intentionally simplified.
      const expectedMsg =
        Interpreter.buildFunctionClauseErrorMsg(":lists.keytake/4");

      const tuples = Type.improperList([
        Type.tuple([atomB]),
        Type.tuple([atomC]),
        Type.tuple([atomD]),
      ]);

      assertBoxedError(
        () => keytake(atomA, integer1, tuples),
        "FunctionClauseError",
        expectedMsg,
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
            return Type.tuple([
              Erlang["*/2"](context.vars.elem, Type.integer(10)),
              Erlang["+/2"](context.vars.acc, context.vars.elem),
            ]);
          },
        },
      ],
      contextFixture(),
    );

    const mapfoldl = Erlang_Lists["mapfoldl/3"];
    const acc = integer0;

    it("mapfolds empty list", () => {
      const result = mapfoldl(fun, acc, emptyList);
      const expected = Type.tuple([emptyList, acc]);

      assert.deepStrictEqual(result, expected);
    });

    it("mapfolds non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = mapfoldl(fun, acc, list);

      const expected = Type.tuple([
        Type.list([Type.integer(10), Type.integer(20), Type.integer(30)]),
        Type.integer(6),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.mapfoldl/3",
        [Type.atom("abc"), acc, emptyList],
      );

      assertBoxedError(
        () => mapfoldl(Type.atom("abc"), acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 2", () => {
      const funArity1 = Type.anonymousFunction(
        1,
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

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.mapfoldl/3",
        [funArity1, acc, emptyList],
      );

      assertBoxedError(
        () => mapfoldl(funArity1, acc, emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the third argument is not a list", () => {
      const invalidArg = Type.atom("abc");

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.mapfoldl_1/3",
        [fun, acc, invalidArg],
      );

      assertBoxedError(
        () => mapfoldl(fun, acc, invalidArg),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the third argument is an improper list", () => {
      const list = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.mapfoldl_1/3",
        [fun, Type.integer(3), Type.integer(3)],
      );

      assertBoxedError(
        () => mapfoldl(fun, acc, list),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises MatchError if the anonymous function does not return a 2-element tuple", () => {
      const invalidFun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("elem"),
              Type.variablePattern("acc"),
            ],
            guards: [],
            body: (context) => {
              return Erlang["+/2"](context.vars.elem, context.vars.acc);
            },
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => mapfoldl(invalidFun, acc, Type.list([integer1])),
        "MatchError",
        Interpreter.buildMatchErrorMsg(integer1),
      );
    });
  });

  describe("max/1", () => {
    const max = Erlang_Lists["max/1"];
    const shuffle = (array) => array.sort(() => Math.random() - 0.5);

    it("returns the element from a list of length 1", () => {
      const list = Type.list([integer3]);
      const result = max(list);

      assert.deepStrictEqual(result, integer3);
    });

    it("returns the larger element from a list of size 2 with second being largest", () => {
      const list = Type.list([integer1, integer3]);
      const result = max(list);

      assertBoxedStrictEqual(result, integer3);
    });

    it("returns the larger element from a list of size 2 with first being largest", () => {
      const list = Type.list([integer3, integer1]);
      const result = max(list);

      assertBoxedStrictEqual(result, integer3);
    });

    it("returns the element from a list of size 2 when both are the same", () => {
      const list = Type.list([integer3, integer3]);
      const result = max(list);

      assertBoxedStrictEqual(result, integer3);
    });

    it("applies structural comparison", () => {
      const data = [
        atomA,
        float2,
        integer3,
        Type.bitstring("d"),
        Type.pid("my_node", [0, 1, 2]),
        Type.tuple([integer0, integer1]),
      ];

      const list = Type.list(shuffle(data));
      const result = max(list);

      assertBoxedStrictEqual(result, Type.bitstring("d"));
    });

    it("returns the largest element from a large list with many duplicates", () => {
      const data = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5].map(
        Type.integer,
      );

      const list = Type.list(shuffle(data));
      const result = max(list);

      assertBoxedStrictEqual(result, integer5);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.max/1",
        [atomAbc],
      );

      assertBoxedError(
        () => max(atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the argument is an improper list", () => {
      // Notice that the error message says :lists.max/2 (not :lists.max/1)
      // :lists.max/2 is (probably) a private Erlang function that get's called by :lists.max/1
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.max/2",
        [improperList],
      );

      assertBoxedError(
        () => max(improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the argument is an empty list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.max/1",
        [emptyList],
      );

      assertBoxedError(
        () => max(emptyList),
        "FunctionClauseError",
        expectedMessage,
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

  describe("min/1", () => {
    const min = Erlang_Lists["min/1"];
    const shuffle = (array) => array.sort(() => Math.random() - 0.5);

    it("returns the element from a list of length 1", () => {
      const list = Type.list([integer3]);
      const result = min(list);

      assert.deepStrictEqual(result, integer3);
    });

    it("returns the smaller element from a list of size 2 with first being smallest", () => {
      const list = Type.list([integer1, integer3]);
      const result = min(list);

      assertBoxedStrictEqual(result, integer1);
    });

    it("returns the smaller element from a list of size 2 with second being smallest", () => {
      const list = Type.list([integer3, integer1]);
      const result = min(list);

      assertBoxedStrictEqual(result, integer1);
    });

    it("returns the element from a list of size 2 when both are the same", () => {
      const list = Type.list([integer3, integer3]);
      const result = min(list);

      assertBoxedStrictEqual(result, integer3);
    });

    it("applies structural comparison", () => {
      const data = [
        atomA,
        float2,
        integer3,
        Type.bitstring("d"),
        Type.pid("my_node", [0, 1, 2]),
        Type.tuple([integer0, integer1]),
      ];

      const list = Type.list(shuffle(data));
      const result = min(list);

      assertBoxedStrictEqual(result, float2);
    });

    it("returns the smallest element from a large list with many duplicates", () => {
      const data = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5].map(
        Type.integer,
      );

      const list = Type.list(shuffle(data));
      const result = min(list);

      assertBoxedStrictEqual(result, integer1);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.min/1",
        [atomAbc],
      );

      assertBoxedError(
        () => min(atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the argument is an improper list", () => {
      // Notice that the error message says :lists.min/2 (not :lists.min/1)
      // :lists.min/2 is (probably) a private Erlang function that get's called by :lists.min/1
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.min/2",
        [improperList],
      );

      assertBoxedError(
        () => min(improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the argument is an empty list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.min/1",
        [emptyList],
      );

      assertBoxedError(
        () => min(emptyList),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });

  describe("prefix/2", () => {
    const prefix = Erlang_Lists["prefix/2"];

    it("returns true if the first one-element list is a prefix of the second list", () => {
      const result = prefix(list1, list2);

      assertBoxedTrue(result);
    });

    it("returns true if the first multiple-element list is a prefix of the second list", () => {
      const result = prefix(list2, list3);

      assertBoxedTrue(result);
    });

    it("returns true if the lists are the same", () => {
      const result = prefix(list2, list2);

      assertBoxedTrue(result);
    });

    it("returns true if both lists contain the same single element", () => {
      const result = prefix(list1, list1);

      assertBoxedTrue(result);
    });

    it("returns true if both lists are empty", () => {
      const result = prefix(Type.list(), Type.list());

      assertBoxedTrue(result);
    });

    it("returns true when the first list is empty", () => {
      const result = prefix(Type.list(), list2);

      assertBoxedTrue(result);
    });

    it("returns false if the first list is not a prefix of the second list", () => {
      const result = prefix(list2, list1);

      assertBoxedFalse(result);
    });

    it("returns false if the first list has an element that differs from the corresponding element in the second list", () => {
      const result = prefix(
        Type.list([Type.integer(1), Type.integer(3)]),
        list3,
      );

      assertBoxedFalse(result);
    });

    it("returns false if the first argument is an improper list that has no common prefix with the second proper list", () => {
      const result = prefix(
        Type.improperList([Type.integer(1), Type.integer(2)]),
        Type.list([Type.integer(3), Type.integer(4)]),
      );

      assertBoxedFalse(result);
    });

    it("returns false if the first argument is an improper list that shares a shorter prefix with the second proper list", () => {
      const result = prefix(
        Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.list([Type.integer(1), Type.integer(4)]),
      );

      assertBoxedFalse(result);
    });

    it("returns false if the second argument is an improper list that has no common prefix with the first proper list", () => {
      const result = prefix(
        Type.list([Type.integer(1), Type.integer(2)]),
        Type.improperList([Type.integer(3), Type.integer(4)]),
      );

      assertBoxedFalse(result);
    });

    it("returns false if the second argument is an improper list that shares a shorter prefix with the first proper list", () => {
      const result = prefix(
        Type.list([Type.integer(1), Type.integer(4)]),
        Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );

      assertBoxedFalse(result);
    });

    it("returns false if both lists are improper with no common prefix", () => {
      const result = prefix(
        Type.improperList([Type.integer(1), Type.integer(2)]),
        Type.improperList([Type.integer(3), Type.integer(4)]),
      );

      assertBoxedFalse(result);
    });

    it("returns false if both lists are improper with a common shorter prefix", () => {
      const result = prefix(
        Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.improperList([Type.integer(1), Type.integer(4), Type.integer(3)]),
      );

      assertBoxedFalse(result);
    });

    it("raises FunctionClauseError if the first argument is not a list", () => {
      assertBoxedError(
        () => prefix(Type.atom("a"), list2),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          Type.atom("a"),
          list2,
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument is not a list", () => {
      assertBoxedError(
        () => prefix(list2, Type.atom("a")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          list2,
          Type.atom("a"),
        ]),
      );
    });

    it("raises FunctionClauseError if the first argument is an improper list where everything but the last element is a prefix of the second proper list", () => {
      assertBoxedError(
        () =>
          prefix(
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
            Type.list([Type.integer(1), Type.integer(2)]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          Type.integer(3),
          emptyList,
        ]),
      );
    });

    it("raises FunctionClauseError if the second argument is an improper list where everything but the last element is a prefix of the first proper list", () => {
      assertBoxedError(
        () =>
          prefix(
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          emptyList,
          Type.integer(3),
        ]),
      );
    });

    it("raises FunctionClauseError if both lists are improper and have a common prefix made of everything but the last element", () => {
      assertBoxedError(
        () =>
          prefix(
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(4),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          Type.integer(3),
          Type.integer(4),
        ]),
      );
    });

    it("raises FunctionClauseError if the first improper list would be a prefix of the second improper list had the first list been proper", () => {
      assertBoxedError(
        () =>
          prefix(
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
              Type.integer(4),
            ]),
          ),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          Type.integer(3),
          Type.improperList([Type.integer(3), Type.integer(4)]),
        ]),
      );
    });
  });

  describe("reverse/2", () => {
    const reverse = Erlang_Lists["reverse/2"];

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

  describe("seq/2", () => {
    const seq = Erlang_Lists["seq/2"];

    it("delegates to seq/3 with increment = 1", () => {
      const result = seq(Type.integer(3), Type.integer(5));

      const expected = Erlang_Lists["seq/3"](
        Type.integer(3),
        Type.integer(5),
        Type.integer(1),
      );

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an integer", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.seq/2",
        [Type.atom("abc"), Type.integer(5)],
      );

      assertBoxedError(
        () => seq(Type.atom("abc"), Type.integer(5)),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is not an integer", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.seq/2",
        [Type.integer(1), Type.atom("abc")],
      );

      assertBoxedError(
        () => seq(Type.integer(1), Type.atom("abc")),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when from > to + 1", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.seq/2",
        [Type.integer(10), Type.integer(5)],
      );

      assertBoxedError(
        () => seq(Type.integer(10), Type.integer(5)),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });

  describe("seq/3", () => {
    const seq = Erlang_Lists["seq/3"];

    it("generates ascending sequence with increment 1", () => {
      const result = seq(Type.integer(3), Type.integer(5), Type.integer(1));

      const expected = Type.list([
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates ascending sequence with increment 2", () => {
      const result = seq(Type.integer(1), Type.integer(10), Type.integer(2));

      const expected = Type.list([
        Type.integer(1),
        Type.integer(3),
        Type.integer(5),
        Type.integer(7),
        Type.integer(9),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates ascending sequence from negative to positive", () => {
      const result = seq(Type.integer(-5), Type.integer(5), Type.integer(2));

      const expected = Type.list([
        Type.integer(-5),
        Type.integer(-3),
        Type.integer(-1),
        Type.integer(1),
        Type.integer(3),
        Type.integer(5),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates descending sequence with negative increment", () => {
      const result = seq(Type.integer(10), Type.integer(5), Type.integer(-1));

      const expected = Type.list([
        Type.integer(10),
        Type.integer(9),
        Type.integer(8),
        Type.integer(7),
        Type.integer(6),
        Type.integer(5),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates descending sequence with negative increment of -2", () => {
      const result = seq(Type.integer(10), Type.integer(1), Type.integer(-2));

      const expected = Type.list([
        Type.integer(10),
        Type.integer(8),
        Type.integer(6),
        Type.integer(4),
        Type.integer(2),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates descending sequence in negative range", () => {
      const result = seq(Type.integer(-1), Type.integer(-10), Type.integer(-2));

      const expected = Type.list([
        Type.integer(-1),
        Type.integer(-3),
        Type.integer(-5),
        Type.integer(-7),
        Type.integer(-9),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates single element sequence when from equals to", () => {
      const result = seq(Type.integer(5), Type.integer(5), Type.integer(1));
      const expected = Type.list([Type.integer(5)]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates single element sequence when from equals to with increment 0", () => {
      const result = seq(Type.integer(5), Type.integer(5), Type.integer(0));
      const expected = Type.list([Type.integer(5)]);

      assert.deepStrictEqual(result, expected);
    });

    it("generates empty sequence if from > to with positive increment", () => {
      const result = seq(Type.integer(10), Type.integer(6), Type.integer(4));
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("generates empty sequence when from - incr equals to (boundary case)", () => {
      const result = seq(Type.integer(3), Type.integer(2), Type.integer(1));
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("generates empty sequence if from < to with negative increment", () => {
      const result = seq(Type.integer(6), Type.integer(7), Type.integer(-1));
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the first argument is not an integer", () => {
      assertBoxedError(
        () => seq(Type.atom("abc"), Type.integer(5), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument is not an integer", () => {
      assertBoxedError(
        () => seq(Type.integer(1), Type.atom("abc"), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the third argument is not an integer", () => {
      assertBoxedError(
        () => seq(Type.integer(1), Type.integer(5), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    });

    it("raises ArgumentError if from > to with positive increment", () => {
      assertBoxedError(
        () => seq(Type.integer(10), Type.integer(1), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a negative increment"),
      );
    });

    it("raises ArgumentError if from < to with negative increment", () => {
      assertBoxedError(
        () => seq(Type.integer(1), Type.integer(10), Type.integer(-1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a positive increment"),
      );
    });

    it("raises ArgumentError if increment is 0", () => {
      assertBoxedError(
        () => seq(Type.integer(1), Type.integer(5), Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a positive increment"),
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
    const sort = Erlang_Lists["sort/2"];

    const fun = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("a"),
            Type.variablePattern("b"),
          ],
          guards: [],
          body: (context) => {
            return Erlang["=</2"](context.vars.a, context.vars.b);
          },
        },
      ],
      contextFixture(),
    );

    it("sorts list using custom comparison function", () => {
      const list = Type.list([integer3, integer1, integer4, integer2]);

      const result = sort(fun, list);
      const expected = Type.list([integer1, integer2, integer3, integer4]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns empty list when sorting empty list", () => {
      const result = sort(fun, emptyList);

      assert.deepStrictEqual(result, emptyList);
    });

    it("returns same list when sorting single element list", () => {
      const list = Type.list([integer5]);
      const result = sort(fun, list);

      assert.deepStrictEqual(result, list);
    });

    it("returns same list when already sorted", () => {
      const list = Type.list([integer1, integer2, integer3, integer4]);
      const result = sort(fun, list);

      assert.deepStrictEqual(result, list);
    });

    it("preserves duplicate elements", () => {
      const list = Type.list([
        integer3,
        integer1,
        integer2,
        integer1,
        integer3,
      ]);

      const result = sort(fun, list);

      const expected = Type.list([
        integer1,
        integer1,
        integer2,
        integer3,
        integer3,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("sorts list in reverse order", () => {
      const reverseFun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("a"),
              Type.variablePattern("b"),
            ],
            guards: [],
            body: (context) => {
              return Erlang[">=/2"](context.vars.a, context.vars.b);
            },
          },
        ],
        contextFixture(),
      );

      const list = Type.list([integer3, integer1, integer4, integer2]);

      const result = sort(reverseFun, list);
      const expected = Type.list([integer4, integer3, integer2, integer1]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises BadFunctionError if the first argument is not a function", () => {
      const expectedMessage = "expected a function, got: :abc";
      const list = Type.list([integer1, integer2]);

      assertBoxedError(
        () => sort(atomAbc, list),
        "BadFunctionError",
        expectedMessage,
      );
    });

    it("raises BadArityError if the first argument is a function with wrong arity", () => {
      const wrongArityFun = Type.anonymousFunction(
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

      const expectedMessage =
        /with arity 1 called with 2 arguments \(\d+, \d+\)/;

      const list = Type.list([integer1, integer2]);

      assertBoxedError(
        () => sort(wrongArityFun, list),
        "BadArityError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is not a list", () => {
      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.sort/2",
        [fun, atomAbc],
      );

      assertBoxedError(
        () => sort(fun, atomAbc),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError if the second argument is an improper list with 2 elements", () => {
      const improperList = Type.improperList([integer1, integer2]);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":lists.sort/2",
        [fun, improperList],
      );

      assertBoxedError(
        () => sort(fun, improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    // Client-side implementation uses simplified error details
    it("raises FunctionClauseError if the second argument is an improper list with at least 3 elements", () => {
      const expectedMessage =
        Interpreter.buildFunctionClauseErrorMsg(":lists.fsplit_1/6");

      assertBoxedError(
        () => sort(fun, improperList),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});

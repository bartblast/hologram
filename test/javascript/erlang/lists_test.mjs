"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  linkModules,
  unlinkModules,
} from "../support/helpers.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/lists_test.exs
// Always update both together.

describe("flatten/1", () => {
  it("works with empty list", () => {
    const emptyList = Type.list([]);
    const result = Erlang_Lists["flatten/1"](emptyList);

    assert.deepStrictEqual(result, emptyList);
  });

  it("works with non-nested list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["flatten/1"](list);

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

    const result = Erlang_Lists["flatten/1"](list);

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
    assertBoxedError(
      () => Erlang_Lists["flatten/1"](Type.atom("abc")),
      "FunctionClauseError",
      "no function clause matching in :lists.flatten/1",
    );
  });
});

describe("foldl/3", () => {
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
  const emptyList = Type.list([]);

  it("reduces empty list", () => {
    const result = Erlang_Lists["foldl/3"](fun, acc, emptyList);

    assert.deepStrictEqual(result, acc);
  });

  it("reduces non-empty list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["foldl/3"](fun, acc, list);

    assert.deepStrictEqual(result, Type.integer(6));
  });

  it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
    assertBoxedError(
      () => Erlang_Lists["foldl/3"](Type.atom("abc"), acc, emptyList),
      "FunctionClauseError",
      "no function clause matching in :lists.foldl/3",
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

    assertBoxedError(
      () => Erlang_Lists["foldl/3"](fun, acc, emptyList),
      "FunctionClauseError",
      "no function clause matching in :lists.foldl/3",
    );
  });

  it("raises CaseClauseError if the third argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Lists["foldl/3"](fun, acc, Type.atom("abc")),
      "CaseClauseError",
      "no case clause matching: :abc",
    );
  });
});

describe("keyfind/3", () => {
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

    const result = Erlang_Lists["keyfind/3"](
      Type.integer(7),
      Type.integer(3),
      tuples,
    );

    assert.deepStrictEqual(result, tuple);
  });

  it("returns false if there is no tuple that fulfills the given conditions", () => {
    const result = Erlang_Lists["keyfind/3"](
      Type.integer(7),
      Type.integer(3),
      Type.list([Type.atom("abc")]),
    );

    assertBoxedFalse(result);
  });

  it("raises ArgumentError if the second argument (index) is not an integer", () => {
    assertBoxedError(
      () =>
        Erlang_Lists["keyfind/3"](
          Type.atom("abc"),
          Type.atom("xyz"),
          Type.list([]),
        ),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "not an integer"),
    );
  });

  it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
    assertBoxedError(
      () =>
        Erlang_Lists["keyfind/3"](
          Type.atom("abc"),
          Type.integer(0),
          Type.list([]),
        ),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "out of range"),
    );
  });

  it("raises ArgumentError if the third argument (tuples) is not a list", () => {
    assertBoxedError(
      () =>
        Erlang_Lists["keyfind/3"](
          Type.atom("abc"),
          Type.integer(1),
          Type.atom("xyz"),
        ),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(3, "not a list"),
    );
  });
});

describe("keymember/3", () => {
  const fun = Erlang_Lists["keymember/3"];

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

    const result = fun(Type.integer(7), Type.integer(3), tuples);

    assertBoxedTrue(result);
  });

  it("returns false if there is no tuple that fulfills the given conditions", () => {
    const result = fun(
      Type.integer(7),
      Type.integer(3),
      Type.list([Type.atom("abc")]),
    );

    assertBoxedFalse(result);
  });

  it("raises ArgumentError if the second argument (index) is not an integer", () => {
    assertBoxedError(
      () => fun(Type.atom("abc"), Type.atom("xyz"), Type.list([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "not an integer"),
    );
  });

  it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
    assertBoxedError(
      () => fun(Type.atom("abc"), Type.integer(0), Type.list([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "out of range"),
    );
  });

  it("raises ArgumentError if the third argument (tuples) is not a list", () => {
    assertBoxedError(
      () => fun(Type.atom("abc"), Type.integer(1), Type.atom("xyz")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(3, "not a list"),
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

  const emptyList = Type.list([]);

  it("maps empty list", () => {
    const result = Erlang_Lists["map/2"](fun, emptyList);
    assert.deepStrictEqual(result, emptyList);
  });

  it("maps non-empty list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["map/2"](fun, list);

    const expected = Type.list([
      Type.integer(10),
      Type.integer(20),
      Type.integer(30),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
    assertBoxedError(
      () => Erlang_Lists["map/2"](Type.atom("abc"), emptyList),
      "FunctionClauseError",
      "no function clause matching in :lists.map/2",
    );
  });

  it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 1", () => {
    const fun = Type.anonymousFunction(
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

    assertBoxedError(
      () => Erlang_Lists["map/2"](fun, emptyList),
      "FunctionClauseError",
      "no function clause matching in :lists.map/2",
    );
  });

  it("raises CaseClauseError if the second argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Lists["map/2"](fun, Type.atom("abc")),
      "CaseClauseError",
      "no case clause matching: :abc",
    );
  });
});

describe("member/2", () => {
  it("is a member", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["member/2"](Type.integer(2), list);

    assertBoxedTrue(result);
  });

  it("is not a member", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["member/2"](Type.integer(4), list);

    assertBoxedFalse(result);
  });

  it("uses strict equality", () => {
    const list = Type.list([Type.integer(1), Type.float(2.0), Type.integer(3)]);
    const result = Erlang_Lists["member/2"](Type.integer(2), list);

    assertBoxedFalse(result);
  });

  it("raises ArgumentError if the second argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Lists["member/2"](Type.integer(2), Type.atom("abc")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "not a list"),
    );
  });
});

describe("reverse/1", () => {
  it("returns a list with the elements in the argument in reverse order", () => {
    const arg = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["reverse/1"](arg);

    const expected = Type.list([
      Type.integer(3),
      Type.integer(2),
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises FunctionClauseError if the argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Lists["reverse/1"](Type.atom("abc")),
      "FunctionClauseError",
      "no function clause matching in :lists.reverse/1",
    );
  });
});

describe("sort/1", () => {
  const fun = Erlang_Lists["sort/1"];

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
      fun(list),
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
    assertBoxedError(
      () => fun(Type.atom("abc")),
      "FunctionClauseError",
      "no function clause matching in :lists.sort/1",
    );
  });
});

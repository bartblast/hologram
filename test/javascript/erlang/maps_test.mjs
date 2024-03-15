"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  buildContext,
  freeze,
  linkModules,
  unlinkModules,
} from "../support/helpers.mjs";

import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

const atomA = freeze(Type.atom("a"));
const atomAbc = freeze(Type.atom("abc"));
const atomB = freeze(Type.atom("b"));
const atomC = freeze(Type.atom("c"));
const integer1 = freeze(Type.integer(1));
const integer2 = freeze(Type.integer(2));

const mapA1B2 = freeze(
  Type.map([
    [atomA, integer1],
    [atomB, integer2],
  ]),
);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/maps_test.exs
// Always update both together.

describe("fold/3", () => {
  let fun, map;

  beforeEach(() => {
    fun = Type.anonymousFunction(
      3,
      [
        {
          params: (_vars) => [
            Type.variablePattern("key"),
            Type.variablePattern("value"),
            Type.variablePattern("acc"),
          ],
          guards: [],
          body: (vars) =>
            Erlang["+/2"](vars.acc, Erlang["*/2"](vars.key, vars.value)),
        },
      ],
      buildContext(),
    );

    map = Type.map([
      [Type.integer(1), Type.integer(1)],
      [Type.integer(10), Type.integer(2)],
      [Type.integer(100), Type.integer(3)],
    ]);
  });

  it("reduces empty map", () => {
    const result = Erlang_Maps["fold/3"](fun, Type.integer(10), Type.map([]));
    assert.deepStrictEqual(result, Type.integer(10));
  });

  it("reduces non-empty map", () => {
    const result = Erlang_Maps["fold/3"](fun, Type.integer(10), map);
    assert.deepStrictEqual(result, Type.integer(331));
  });

  it("raises ArgumentError if the first argument is not an anonymous function", () => {
    assertBoxedError(
      () =>
        Erlang_Maps["fold/3"](Type.atom("abc"), Type.integer(10), Type.map([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(
        1,
        "not a fun that takes three arguments",
      ),
    );
  });

  it("raises ArgumentError if the first argument is an anonymous function with arity different than 3", () => {
    fun = Type.anonymousFunction(
      0,
      [{params: (_vars) => [], guards: [], body: (_vars) => Type.atom("abc")}],
      buildContext(),
    );

    assertBoxedError(
      () => Erlang_Maps["fold/3"](fun, Type.integer(10), Type.map([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(
        1,
        "not a fun that takes three arguments",
      ),
    );
  });

  it("raises BadMapError if the third argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["fold/3"](fun, Type.integer(10), Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("from_list/1", () => {
  it("builds a map from the given list of key-value tuples", () => {
    const list = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(2)]),
      Type.tuple([Type.integer(3), Type.float(4.0)]),
    ]);

    const result = Erlang_Maps["from_list/1"](list);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(2)],
      [Type.integer(3), Type.float(4.0)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("if the same key appears more than once, the latter (right-most) value is used and the previous values are ignored", () => {
    const list = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.tuple([Type.atom("a"), Type.integer(3)]),
      Type.tuple([Type.atom("b"), Type.integer(4)]),
      Type.tuple([Type.atom("a"), Type.integer(5)]),
      Type.tuple([Type.atom("b"), Type.integer(6)]),
    ]);

    const result = Erlang_Maps["from_list/1"](list);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(5)],
      [Type.atom("b"), Type.integer(6)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises ArgumentError if the argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Maps["from_list/1"](Type.integer(123)),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a list"),
    );
  });
});

describe("get/2", () => {
  it("returns the value assiociated with the given key if map contains the key", () => {
    const key = Type.atom("b");
    const value = Type.integer(2);

    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [key, value],
    ]);

    const result = Erlang_Maps["get/2"](key, map);

    assert.deepStrictEqual(result, value);
  });

  it("raises BadMapError if the second argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["get/2"](Type.atom("a"), Type.integer(1)),
      "BadMapError",
      "expected a map, got: 1",
    );
  });

  it("raises KeyError if the map doesn't contain the given key", () => {
    assertBoxedError(
      () => Erlang_Maps["get/2"](Type.atom("a"), Type.map([])),
      "KeyError",
      "key :a not found in: %{}",
    );
  });
});

describe("get/3", () => {
  const defaultValue = Type.atom("default_value");

  it("returns the value assiociated with the given key if map contains the key", () => {
    const key = Type.atom("b");
    const value = Type.integer(2);

    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [key, value],
    ]);

    const result = Erlang_Maps["get/3"](key, map, defaultValue);

    assert.deepStrictEqual(result, value);
  });

  it("raises BadMapError if the second argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["get/3"](Type.atom("a"), Type.integer(1), defaultValue),
      "BadMapError",
      "expected a map, got: 1",
    );
  });

  it("returns the default value if the map doesn't contain the given key", () => {
    const result = Erlang_Maps["get/3"](
      Type.atom("a"),
      Type.map([]),
      defaultValue,
    );
    assert.deepStrictEqual(result, defaultValue);
  });
});

describe("is_key/2", () => {
  const fun = Erlang_Maps["is_key/2"];

  it("returns true if the given map has the given key", () => {
    assertBoxedTrue(fun(atomB, mapA1B2));
  });

  it("returns false if the given map doesn't have the given key", () => {
    assertBoxedFalse(fun(atomC, mapA1B2));
  });

  it("raises BadMapError if the second argument is not a map", () => {
    assertBoxedError(
      () => fun(atomA, atomAbc),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("map/2", () => {
  const fun = Type.anonymousFunction(
    2,
    [
      {
        params: (_vars) => [
          Type.matchPlaceholder(),
          Type.variablePattern("value"),
        ],
        guards: [],
        body: (vars) => {
          return Erlang["*/2"](vars.value, Type.integer(10));
        },
      },
    ],
    buildContext(),
  );

  it("maps empty map", () => {
    const result = Erlang_Maps["map/2"](fun, Type.map([]));
    assert.deepStrictEqual(result, Type.map([]));
  });

  it("maps non-empty map", () => {
    const result = Erlang_Maps["map/2"](
      fun,
      Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("c"), Type.integer(3)],
      ]),
    );

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("a"), Type.integer(10)],
        [Type.atom("b"), Type.integer(20)],
        [Type.atom("c"), Type.integer(30)],
      ]),
    );
  });

  it("raises ArgumentError if the first argument is not an anonymous function", () => {
    assertBoxedError(
      () => Erlang_Maps["map/2"](Type.atom("abc"), Type.map([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a fun that takes two arguments"),
    );
  });

  it("raises ArgumentError if the first argument is an anonymous function with arity different than 2", () => {
    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_vars) => [Type.variablePattern("x")],
          guards: [],
          body: (vars) => {
            return vars.x;
          },
        },
      ],
      buildContext(),
    );

    assertBoxedError(
      () => Erlang_Maps["map/2"](fun, Type.map([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a fun that takes two arguments"),
    );
  });

  it("raises BadMapError if the second argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["map/2"](fun, Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("merge/2", () => {
  it("merges two maps", () => {
    const map1 = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const map2 = Type.map([
      [Type.atom("c"), Type.integer(3)],
      [Type.atom("d"), Type.integer(4)],
    ]);

    const result = Erlang_Maps["merge/2"](map1, map2);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
      [Type.atom("d"), Type.integer(4)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("if two keys exist in both maps, the value in the first map is superseded by the value in the second map", () => {
    const map1 = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ]);

    const map2 = Type.map([
      [Type.atom("c"), Type.integer(4)],
      [Type.atom("d"), Type.integer(5)],
      [Type.atom("a"), Type.integer(6)],
    ]);

    const result = Erlang_Maps["merge/2"](map1, map2);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(6)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(4)],
      [Type.atom("d"), Type.integer(5)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises BadMapError if the first argument is not a map", () => {
    const map = Type.map([[Type.atom("a"), Type.integer(1)]]);

    assertBoxedError(
      () => Erlang_Maps["merge/2"](Type.integer(123), map),
      "BadMapError",
      "expected a map, got: 123",
    );
  });

  it("raises BadMapError if the second argument is not a map", () => {
    const map = Type.map([[Type.atom("a"), Type.integer(1)]]);

    assertBoxedError(
      () => Erlang_Maps["merge/2"](map, Type.integer(123)),
      "BadMapError",
      "expected a map, got: 123",
    );
  });
});

describe("put/3", () => {
  it("when the map doesn't have the given key", () => {
    const map = Type.map([[Type.atom("a"), Type.integer(1)]]);
    const result = Erlang_Maps["put/3"](Type.atom("b"), Type.integer(2), map);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("when the map already has the given key", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Erlang_Maps["put/3"](Type.atom("b"), Type.integer(3), map);

    const expected = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(3)],
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises BadMapError if the third argument is not a map", () => {
    assertBoxedError(
      () =>
        Erlang_Maps["put/3"](Type.atom("a"), Type.integer(1), Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("to_list/1", () => {
  it("doesn't mutate its arguments", () => {
    Erlang_Maps["to_list/1"](
      freeze(
        Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      ),
    );
  });

  it("returns an empty list if given an empty map", () => {
    const result = Erlang_Maps["to_list/1"](Type.map([]));
    assert.deepStrictEqual(result, Type.list([]));
  });

  it("returns a list of tuples containing key-value pairs if given a non-empty map", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Erlang_Maps["to_list/1"](map);

    const expected = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises BadMapError if the argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["to_list/1"](Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });

  // TODO: this should fail when iterators get implemented
  it("raises BadMapError if the argument is an iterator", () => {
    const iterator = Type.tuple([
      Type.atom("a"),
      Type.integer(1),
      Type.atom("none"),
    ]);

    assertBoxedError(
      () => Erlang_Maps["to_list/1"](iterator),
      "BadMapError",
      "expected a map, got: {:a, 1, :none}",
    );
  });
});

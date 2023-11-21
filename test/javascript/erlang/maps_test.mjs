"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  freeze,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

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
      {},
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
      "errors were found at the given arguments:\n\n* 1st argument: not a fun that takes three arguments",
    );
  });

  it("raises ArgumentError if the first argument is an anonymous function with arity different than 3", () => {
    fun = Type.anonymousFunction(
      0,
      [{params: (_vars) => [], guards: [], body: (_vars) => Type.atom("abc")}],
      {},
    );

    assertBoxedError(
      () =>
        Erlang_Maps["fold/3"](Type.atom("abc"), Type.integer(10), Type.map([])),
      "ArgumentError",
      "errors were found at the given arguments:\n\n* 1st argument: not a fun that takes three arguments",
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
      "errors were found at the given arguments:\n\n* 1st argument: not a list",
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
      "key :a not found in %{}",
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
  const map = Type.map([
    [Type.atom("a"), Type.integer(1)],
    [Type.atom("b"), Type.integer(2)],
  ]);

  it("doesn't mutate its arguments", () => {
    Erlang_Maps["is_key/2"](
      freeze(Type.atom("a")),
      freeze(Type.map([[Type.atom("a"), Type.integer(1)]])),
    );
  });

  it("returns true if the given map has the given key", () => {
    assertBoxedTrue(Erlang_Maps["is_key/2"](Type.atom("b"), map));
  });

  it("returns false if the given map has the given key", () => {
    assertBoxedFalse(Erlang_Maps["is_key/2"](Type.atom("c"), map));
  });

  it("raises BadMapError if the second argument is not a map", () => {
    assertBoxedError(
      () => Erlang_Maps["is_key/2"](Type.atom("x"), Type.atom("abc")),
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

describe("puts/3", () => {
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

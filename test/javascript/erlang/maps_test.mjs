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

import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

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

describe("Erlang_Maps", () => {
  describe("fold/3", () => {
    const fold = Erlang_Maps["fold/3"];

    let fun, map;

    beforeEach(() => {
      fun = Type.anonymousFunction(
        3,
        [
          {
            params: (_context) => [
              Type.variablePattern("key"),
              Type.variablePattern("value"),
              Type.variablePattern("acc"),
            ],
            guards: [],
            body: (context) =>
              Erlang["+/2"](
                context.vars.acc,
                Erlang["*/2"](context.vars.key, context.vars.value),
              ),
          },
        ],
        contextFixture(),
      );

      map = Type.map([
        [Type.integer(1), Type.integer(1)],
        [Type.integer(10), Type.integer(2)],
        [Type.integer(100), Type.integer(3)],
      ]);
    });

    it("reduces empty map", () => {
      const result = fold(fun, Type.integer(10), Type.map());
      assert.deepStrictEqual(result, Type.integer(10));
    });

    it("reduces non-empty map", () => {
      const result = fold(fun, Type.integer(10), map);
      assert.deepStrictEqual(result, Type.integer(331));
    });

    it("raises ArgumentError if the first argument is not an anonymous function", () => {
      assertBoxedError(
        () => fold(Type.atom("abc"), Type.integer(10), Type.map()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes three arguments",
        ),
      );
    });

    it("raises ArgumentError if the first argument is an anonymous function with arity different than 3", () => {
      fun = Type.anonymousFunction(
        0,
        [
          {
            params: (_context) => [],
            guards: [],
            body: (_context) => Type.atom("abc"),
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => fold(fun, Type.integer(10), Type.map()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes three arguments",
        ),
      );
    });

    it("raises BadMapError if the third argument is not a map", () => {
      assertBoxedError(
        () => fold(fun, Type.integer(10), Type.atom("abc")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("from_list/1", () => {
    const from_list = Erlang_Maps["from_list/1"];

    it("builds a map from the given list of key-value tuples", () => {
      const list = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(2)]),
        Type.tuple([Type.integer(3), Type.float(4.0)]),
      ]);

      const result = from_list(list);

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

      const result = from_list(list);

      const expected = Type.map([
        [Type.atom("a"), Type.integer(5)],
        [Type.atom("b"), Type.integer(6)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the argument is not a list", () => {
      assertBoxedError(
        () => from_list(Type.integer(123)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("get/2", () => {
    const get = Erlang_Maps["get/2"];

    it("returns the value assiociated with the given key if map contains the key", () => {
      const key = Type.atom("b");
      const value = Type.integer(2);

      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [key, value],
      ]);

      const result = get(key, map);

      assert.deepStrictEqual(result, value);
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => get(Type.atom("a"), Type.integer(1)),
        "BadMapError",
        "expected a map, got: 1",
      );
    });

    it("raises KeyError if the map doesn't contain the given key", () => {
      const key = Type.atom("a");
      const map = Type.map();

      assertBoxedError(
        () => get(key, map),
        "KeyError",
        Interpreter.buildKeyErrorMsg(key, map),
      );
    });
  });

  describe("get/3", () => {
    const defaultValue = Type.atom("default_value");
    const get = Erlang_Maps["get/3"];

    it("returns the value assiociated with the given key if map contains the key", () => {
      const key = Type.atom("b");
      const value = Type.integer(2);

      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [key, value],
      ]);

      const result = get(key, map, defaultValue);

      assert.deepStrictEqual(result, value);
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => get(Type.atom("a"), Type.integer(1), defaultValue),
        "BadMapError",
        "expected a map, got: 1",
      );
    });

    it("returns the default value if the map doesn't contain the given key", () => {
      const result = get(Type.atom("a"), Type.map(), defaultValue);
      assert.deepStrictEqual(result, defaultValue);
    });
  });

  describe("is_key/2", () => {
    const is_key = Erlang_Maps["is_key/2"];

    it("returns true if the given map has the given key", () => {
      assertBoxedTrue(is_key(atomB, mapA1B2));
    });

    it("returns false if the given map doesn't have the given key", () => {
      assertBoxedFalse(is_key(atomC, mapA1B2));
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => is_key(atomA, atomAbc),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("iterator/1", () => {
    const iterator = Erlang_Maps["iterator/1"];

    it("empty map", () => {
      const map = Type.map();
      const result = iterator(map);
      const expected = Type.improperList([Type.integer(0), map]);

      assert.deepStrictEqual(result, expected);
    });

    it("non-empty map", () => {
      const map = Type.map([
        [atomA, integer1],
        [atomB, integer2],
      ]);

      const result = iterator(map);
      const expected = Type.improperList([Type.integer(0), map]);

      assert.deepStrictEqual(result, expected);
    });

    it("not a map", () => {
      assertBoxedError(
        () => iterator(atomAbc),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("keys/1", () => {
    const keys = Erlang_Maps["keys/1"];

    it("empty map", () => {
      assert.deepStrictEqual(keys(Type.map()), Type.list());
    });

    it("non-empty map", () => {
      const map = Type.map([
        [atomA, integer1],
        [atomB, integer2],
      ]);

      assert.deepStrictEqual(keys(map), Type.list([atomA, atomB]));
    });

    it("not a map", () => {
      assertBoxedError(
        () => keys(atomAbc),
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
          params: (_context) => [
            Type.matchPlaceholder(),
            Type.variablePattern("value"),
          ],
          guards: [],
          body: (context) => {
            return Erlang["*/2"](context.vars.value, Type.integer(10));
          },
        },
      ],
      contextFixture(),
    );

    const map = Erlang_Maps["map/2"];

    it("maps empty map", () => {
      const result = map(fun, Type.map());
      assert.deepStrictEqual(result, Type.map());
    });

    it("maps non-empty map", () => {
      const result = map(
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
        () => map(Type.atom("abc"), Type.map()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes two arguments",
        ),
      );
    });

    it("raises ArgumentError if the first argument is an anonymous function with arity different than 2", () => {
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
        () => map(fun, Type.map()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes two arguments",
        ),
      );
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => map(fun, Type.atom("abc")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("merge/2", () => {
    const merge = Erlang_Maps["merge/2"];

    it("merges two maps", () => {
      const map1 = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const map2 = Type.map([
        [Type.atom("c"), Type.integer(3)],
        [Type.atom("d"), Type.integer(4)],
      ]);

      const result = merge(map1, map2);

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

      const result = merge(map1, map2);

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
        () => merge(Type.integer(123), map),
        "BadMapError",
        "expected a map, got: 123",
      );
    });

    it("raises BadMapError if the second argument is not a map", () => {
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);

      assertBoxedError(
        () => merge(map, Type.integer(123)),
        "BadMapError",
        "expected a map, got: 123",
      );
    });
  });

  describe("next/1", () => {
    const iterator = Erlang_Maps["iterator/1"];
    const next = Erlang_Maps["next/1"];

    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ]);

    it("initial iterator with empty map", () => {
      const iter = iterator(Type.map());
      const result = next(iter);

      assert.deepStrictEqual(result, Type.atom("none"));
    });

    it("initial iterator with non-empty map", () => {
      const iter = iterator(map);
      const result = next(iter);

      const expected = Type.tuple([
        Type.atom("a"),
        Type.integer(1),
        Type.tuple([
          Type.atom("b"),
          Type.integer(2),
          Type.tuple([Type.atom("c"), Type.integer(3), Type.atom("none")]),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("non-initial empty iterator", () => {
      const iter = next(iterator(Type.map()));
      const result = next(iter);

      assert.deepStrictEqual(result, Type.atom("none"));
    });

    it("non-initial non-empty iterator", () => {
      const iter = next(iterator(map));
      const result = next(iter);

      assert.deepStrictEqual(result, iter);
    });

    it("not an iterator", () => {
      assertBoxedError(
        () => next(Type.integer(123)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a valid iterator"),
      );
    });
  });

  describe("put/3", () => {
    const put = Erlang_Maps["put/3"];

    it("when the map doesn't have the given key", () => {
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);
      const result = put(Type.atom("b"), Type.integer(2), map);

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

      const result = put(Type.atom("b"), Type.integer(3), map);

      const expected = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(3)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises BadMapError if the third argument is not a map", () => {
      assertBoxedError(
        () => put(Type.atom("a"), Type.integer(1), Type.atom("abc")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("remove/2", () => {
    const remove = Erlang_Maps["remove/2"];

    it("when the map has the given key", () => {
      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("c"), Type.integer(3)],
      ]);

      const result = remove(Type.atom("b"), map);

      const expected = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("c"), Type.integer(3)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("when the map doesn't have the given key", () => {
      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("c"), Type.integer(3)],
      ]);

      const result = remove(Type.atom("b"), map);

      const expected = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("c"), Type.integer(3)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => remove(Type.atom("b"), Type.integer(123)),
        "BadMapError",
        "expected a map, got: 123",
      );
    });
  });

  describe("to_list/1", () => {
    const to_list = Erlang_Maps["to_list/1"];

    it("doesn't mutate its arguments", () => {
      to_list(
        freeze(
          Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(2)],
          ]),
        ),
      );
    });

    it("returns an empty list if given an empty map", () => {
      const result = to_list(Type.map());
      assert.deepStrictEqual(result, Type.list());
    });

    it("returns a list of tuples containing key-value pairs if given a non-empty map", () => {
      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const result = to_list(map);

      const expected = Type.list([
        Type.tuple([Type.atom("a"), Type.integer(1)]),
        Type.tuple([Type.atom("b"), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises BadMapError if the argument is not a map", () => {
      assertBoxedError(
        () => to_list(Type.atom("abc")),
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
        () => to_list(iterator),
        "BadMapError",
        "expected a map, got: {:a, 1, :none}",
      );
    });
  });

  describe("update/3", () => {
    const fun = Erlang_Maps["update/3"];

    it("when the map doesn't have the given key", () => {
      const key = Type.atom("b");
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);

      assertBoxedError(
        () => fun(key, Type.integer(2), map),
        "KeyError",
        Interpreter.buildKeyErrorMsg(key, map),
      );
    });

    it("when the map already has the given key", () => {
      const map = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const result = fun(Type.atom("b"), Type.integer(3), map);

      const expected = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(3)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises BadMapError if the third argument is not a map", () => {
      assertBoxedError(
        () => fun(Type.atom("a"), Type.integer(1), Type.atom("abc")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });
});

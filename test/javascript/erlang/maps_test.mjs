"use strict";

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

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

  it("raises BadMapError if the map param is not a boxed map", () => {
    const expectedMessage = "expected a map, got: 1";

    assertBoxedError(
      () => Erlang_Maps["get/2"](Type.atom("a"), Type.integer(1)),
      "BadMapError",
      expectedMessage,
    );
  });

  it("raises KeyError if the map doesn't contain the given key", () => {
    const expectedMessage = 'key :a not found in {"type":"map","data":{}}';

    assertBoxedError(
      () => Erlang_Maps["get/2"](Type.atom("a"), Type.map([])),
      "KeyError",
      expectedMessage,
    );
  });
});

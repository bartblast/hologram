"use strict";

import {
  assert,
  assertError,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang_Maps from "../../../assets/js/erlang/maps.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("get/2", () => {
  it("returns the value assiociated with the given key if map contains the key", () => {
    const key = Type.atom("b");
    const value = Type.integer(2);

    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [key, value],
    ]);

    const result = Erlang_Maps.get(key, map);

    assert.deepStrictEqual(result, value);
  });

  it("raises BadMapError if the map param is not a boxed map", () => {
    const expectedMessage = "expected a map, got: 1";
    assertError(
      () => Erlang_Maps.get(Type.atom("a"), Type.integer(1)),
      "BadMapError",
      expectedMessage
    );
  });

  it("raises KeyError if the map doesn't contain the given key", () => {
    const expectedMessage = 'key :a not found in {"type":"map","data":{}}';
    assertError(
      () => Erlang_Maps.get(Type.atom("a"), Type.map([])),
      "KeyError",
      expectedMessage
    );
  });
});

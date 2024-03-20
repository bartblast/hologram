"use strict";

import {
  assert,
  assertFrozen,
  cleanup,
} from "../support/commons";
beforeEach(() => cleanup());

import Map from "../../../assets/js/hologram/elixir/map";
import Type from "../../../assets/js/hologram/type";

describe("put()", () => {
  let map1, map2, result;

  beforeEach(() => {
    let elems1 = {};
    elems1[Type.atomKey("a")] = Type.integer(1);
    elems1[Type.atomKey("b")] = Type.integer(2);
    map1 = Type.map(elems1);

    let elems2 = {};
    elems2[Type.atomKey("a")] = Type.integer(1);
    elems2[Type.atomKey("b")] = Type.integer(2);
    elems2[Type.atomKey("c")] = Type.integer(3);
    map2 = Type.map(elems2);

    result = Map.put(map1, Type.atom("c"), Type.integer(3));
  });

  it("adds the key-value pair to the map when the map doesn't contain the given key yet", () => {
    assert.deepStrictEqual(result, map2);
  });

  it("adds the key-value pair to the map when the map already contains the given key", () => {
    const result = Map.put(map2, Type.atom("c"), Type.integer(3));
    assert.deepStrictEqual(result, map2);
  });

  it("clones the orignal map object", () => {
    assert.notEqual(result, map1);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});

describe("to_list()", () => {
  it("converts empty boxed map to empty boxed list", () => {
    const map = Type.map();

    const result = Map.to_list(map);
    const expected = Type.list();

    assert.deepStrictEqual(result, expected);
  });

  it("converts non-empty boxed map to boxed list consisting of {key, value} tuples", () => {
    let map = Type.map();
    map = Map.put(map, Type.atom("a"), Type.integer(1));
    map = Map.put(map, Type.string("b"), Type.float(2.0));

    const result = Map.to_list(map);

    const expectedData = [
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.string("b"), Type.float(2.0)]),
    ];

    const expected = Type.list(expectedData);

    assert.deepStrictEqual(result, expected);
  });
});

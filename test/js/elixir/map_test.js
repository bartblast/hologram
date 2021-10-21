"use strict";

import { assert, assertFrozen, cleanup } from "../support/commons";
beforeEach(() => cleanup())

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

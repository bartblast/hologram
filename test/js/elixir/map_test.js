"use strict";

import { assert, assertFrozen } from "../support/commons"
import Map from "../../../assets/js/hologram/elixir/map";
import Type from "../../../assets/js/hologram/type";

describe("put()", () => {
  let data, key, map, result, value;

  beforeEach(() => {
    data = {}
    data[Type.atomKey("a")] = Type.integer(1)
    data[Type.atomKey("b")] = Type.integer(2)
    map = Type.map(data)
    
    key = Type.atom("c")
    value = Type.integer(3)

    result = Map.put(map, key, value)
  })

  it("adds the key-value pair to the map", () => {
    data = {}
    data[Type.atomKey("a")] = Type.integer(1)
    data[Type.atomKey("b")] = Type.integer(2)
    data[Type.atomKey("c")] = Type.integer(3)
    const expected = Type.map(data)

    assert.deepStrictEqual(result, expected) 
  })

  it("clones the orignal map object", () => {
    assert.notEqual(result, map)
  })

  it("returns frozen object", () => {    
    assertFrozen(result)
  })
})
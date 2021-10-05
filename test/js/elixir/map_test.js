"use strict";

import { assert, assertFrozen } from "../support/commons"
import Map from "../../../assets/js/hologram/elixir/map";
import Type from "../../../assets/js/hologram/type";

describe("put()", () => {
  let elems, key, map, result, value;

  beforeEach(() => {
    elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    map = Type.map(elems)
    
    key = Type.atom("c")
    value = Type.integer(3)

    result = Map.put(map, key, value)
  })

  it("adds the key-value pair to the map", () => {
    elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    elems[Type.atomKey("c")] = Type.integer(3)
    const expected = Type.map(elems)

    assert.deepStrictEqual(result, expected) 
  })

  it("clones the orignal map object", () => {
    assert.notEqual(result, map)
  })

  it("returns frozen object", () => {    
    assertFrozen(result)
  })
})
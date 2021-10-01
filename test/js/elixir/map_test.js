"use strict";

import { assert } from "../support/commons"
import Map from "../../../assets/js/hologram/elixir/map";

describe("put()", () => {
  it("adds a key-value pair to the map", () => {
    const map =  {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2}
      }
    }
    
    const key = {type: "atom", value: "c"}
    const value = {type: "integer", value: 3}
    const result = Map.put(map, key, value)

    const expected =  {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2},
        "~atom[c]": {type: "integer", value: 3}
      }
    }

    assert.deepStrictEqual(result, expected) 
    assert.notEqual(result, map)
  })
})
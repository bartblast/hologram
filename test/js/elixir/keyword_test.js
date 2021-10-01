"use strict";

import { assert } from "../support/commons"

import Keyword from "../../../assets/js/hologram/elixir/keyword";
import Type from "../../../assets/js/hologram/type";

describe("has_key$question()", () => {
  let keywords;
  beforeEach(() => {
    keywords = {
      type: "list",
      data: [
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "a"},
            {type: "integer", value: 1},
          ]
        },
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "b"},
            {type: "integer", value: 2},
          ]
        }        
      ]
    }
  })
  
  it("has key", () => {
    const key = {type: "atom", value: "b"}
    const result = Keyword.has_key$question(keywords, key)
    const expected = Type.boolean(true)

    assert.deepStrictEqual(result, expected)
  })

  it("doesn't have key", () => {
    const key = {type: "atom", value: "c"}
    const result = Keyword.has_key$question(keywords, key)
    const expected = Type.boolean(false)

    assert.deepStrictEqual(result, expected)
  })
})
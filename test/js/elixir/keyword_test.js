"use strict";

import { assertBoxedFalse, assertBoxedTrue } from "../support/commons"

import Keyword from "../../../assets/js/hologram/elixir/keyword";

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
  
  it("returns boxed true if the keyword list has the key", () => {
    const key = {type: "atom", value: "b"}
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedTrue(result)
  })

  it("returns boxed false if the keyword list doesn't have the key", () => {
    const key = {type: "atom", value: "c"}
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedFalse(result)
  })
})
"use strict";

import { assertBoxedFalse, assertBoxedTrue } from "../support/commons"
import Keyword from "../../../assets/js/hologram/elixir/keyword";
import Type from "../../../assets/js/hologram/type";

describe("has_key$question()", () => {
  let keywords;

  beforeEach(() => {
    keywords = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)])
    ])
  })
  
  it("returns boxed true if the keyword list has the key", () => {
    const key = Type.atom("b")
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedTrue(result)
  })

  it("returns boxed false if the keyword list doesn't have the key", () => {
    const key = Type.atom("c")
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedFalse(result)
  })
})
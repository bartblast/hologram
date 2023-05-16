"use strict";

import { assert, assertFrozen } from "../../assets/js/test_support.mjs";
import Type from "../../assets/js/type.mjs"

describe("atom()", () => {
  it("returns boxed atom value", () => {
    const result = Type.atom("test")
    const expected = {type: "atom", value: "test"}

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(Type.atom("test"))
  })
})

"use strict";

import { assert, assertFrozen } from "../support/commons"
import String from "../../../assets/js/hologram/elixir/string";
import Utils from "../../../assets/js/hologram/utils";

describe("to_atom()", () => {
  let result;

  beforeEach(() => {
    const arg = Utils.freeze({type: "string", value: "test"})
    result = String.to_atom(arg)
  })

  it("converts boxed string to boxed atom", () => {
    const expected = {type: "atom", value: "test"}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})
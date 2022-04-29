"use strict";

import { assert, assertFrozen, cleanup } from "../../support/commons"
beforeEach(() => cleanup())

import SpecialForms from "../../../../assets/js/hologram/elixir/kernel/special_forms"
import Type from "../../../../assets/js/hologram/type";

describe("case()", () => {
  it("evaulates the given anonymous function", () => {
    const expected = Type.integer(1);
    const result = SpecialForms.case(() => { return expected });
    assert.equal(result, expected);
  });

  it("returns frozen object", () => {
    const result = SpecialForms.case(() => { return {test: "test"}});
    assertFrozen(result)
  })
})
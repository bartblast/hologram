"use strict";

import { assert, assertFrozen, cleanup } from "../../support/commons"
beforeEach(() => cleanup())

import { HologramNotImplementedError } from "../../../../assets/js/hologram/errors";
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

describe("$type", () => {
  it("returns the value given in the first arg if it is of boxed string type and if the type arg is binary", () => {
    const value = Type.string("test")
    const result = SpecialForms.$type(value, "binary")

    assert.equal(result, value)
  })

  it("throws an error for not implemented cases", () => {
    const value = Type.string("test")
    const expectedMessage = 'Elixir_Kernel_SpecialForms.$type(): value = {"type":"string","value":"test"}, type = "not implemented"'

    assert.throw(() => { SpecialForms.$type(value, "not implemented") }, HologramNotImplementedError, expectedMessage);
  })
})
"use strict";

import { assert } from "../../support/commons"
import HologramNotImplementedError from "../../../../assets/js/hologram/errors";
import SpecialForms from "../../../../assets/js/hologram/elixir/kernel/special_forms"
import Type from "../../../../assets/js/hologram/type";

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
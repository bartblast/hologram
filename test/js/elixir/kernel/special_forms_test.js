"use strict";

import { assert, assertFrozen, cleanup } from "../../support/commons"
beforeEach(() => cleanup())

import { HologramNotImplementedError } from "../../../../assets/js/hologram/errors";
import SpecialForms from "../../../../assets/js/hologram/elixir/kernel/special_forms"
import Type from "../../../../assets/js/hologram/type";

describe("$dot()", () => {
  let key, map, val, result;

  beforeEach(() => {
    val = Type.integer(2)

    let elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = val

    map =  Type.map(elems)
    key = Type.atom("b")
    
    result = SpecialForms.$dot(map, key)
  })

  it("fetches boxed map value by boxed key", () => {
    assert.deepStrictEqual(result, val) 
  })

  it("returns frozen object", () => {
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
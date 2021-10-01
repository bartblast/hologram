"use strict";

import { assert, assertFreezed } from "./support/commons";
import HologramNotImplementedError from "../../assets/js/hologram/errors";
import Utils from "../../assets/js/hologram/utils";

describe("clone()", () => {
  let obj, result;

  beforeEach(() => {
    obj = {a: 1, b: {c: 3, d: 4}}
    result = Utils.clone(obj)
  })

  it("clones object recursively (deep clone)", () => {
    assert.deepStrictEqual(result, obj) 
    assert.notEqual(result, obj)
  })

  it("returns freezed object", () => {
    assertFreezed(result)
  })
})

describe("eval()", () => {
  let result;

  beforeEach(() => {
    result = Utils.eval("{value: 2 + 2}")
  })

  it("evaluates code", () => {
    assert.deepStrictEqual(result, {value: 4})
  })

  it("returns freezed object", () => {
    assertFreezed(result)
  })
})

describe("freeze()", () => {
  it("freezes object and all of its properties recursively (deep freeze)", () => {
    let obj = {
      a: {
        b: {
          c: {
            d: 1
          }
        }
      }
    }

    Utils.freeze(obj)
    assertFreezed(obj)
  })
})

describe("serialize()", () => {
  it("serializes atom boxed value", () => {
    const arg = {type: "atom", value: "test"}
    const result = Utils.serialize(arg)

    assert.equal(result, "~atom[test]")
  })

  it("serializes string boxed value", () => {
    const arg = {type: "string", value: "test"}
    const result = Utils.serialize(arg)

    assert.equal(result, "~string[test]")
  })

  it("throws an error for not implemented types", () => {
    const arg = {type: "not implemented", value: "test"}
    const expected_message = 'Utils.serialize(): boxedValue = {"type":"not implemented","value":"test"}'
    assert.throw(() => { Utils.serialize(arg) }, HologramNotImplementedError, expected_message);
  })
})
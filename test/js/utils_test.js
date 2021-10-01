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

describe("isFalse()", () => {
  it("returns true for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Utils.isFalse(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed false value", () => {
    const arg = {type: "boolean", value: true}
    const result = Utils.isFalse(arg)
    
    assert.isFalse(result)
  })
})

describe("isFalsy()", () => {
  it("returns true for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Utils.isFalsy(arg)

    assert.isTrue(result)
  })

  it("returns true for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Utils.isFalsy(arg)
    
    assert.isTrue(result)
  })

  it("returns false for values other than boxed false or boxed nil values", () => {
    const arg = {type: "integer", value: 0}
    const result = Utils.isFalsy(arg)

    assert.isFalse(result)
  })
})

describe("isNil()", () => {
  it("returns true for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Utils.isNil(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed nil value", () => {
    const arg = {type: "boolean", value: false}
    const result = Utils.isNil(arg)
    
    assert.isFalse(result)
  })
})

describe("isTruthy()", () => {
  it("returns false for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Utils.isTruthy(arg)

    assert.isFalse(result)
  })

  it("returns false for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Utils.isTruthy(arg)
    
    assert.isFalse(result)
  })

  it("returns true for values other than boxed false or boxed nil values", () => {
    const arg = {type: "integer", value: 0}
    const result = Utils.isTruthy(arg)

    assert.isTrue(result)
  })
})

describe("keywordToMap()", () => {
  it("converts empty boxed keyword list to boxed map", () => {
    const keyword = Object.freeze({type: "list", data: []})

    const result = Utils.keywordToMap(keyword)
    const expected = {type: "map", data: {}}
    
    assert.deepStrictEqual(result, expected) 
  })

  it("converts non-empty boxed keyword list to boxed map ", () => {
    const keyword = Utils.freeze({
      type: "list",
      data: [
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "a"},
            {type: "integer", value: 1}
          ]
        },
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "b"},
            {type: "integer", value: 2}
          ]
        }
      ]
    })

    const result = Utils.keywordToMap(keyword)

    const expected = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2}
      }
    }
    
    assert.deepStrictEqual(result, expected) 
  })

  it("overwrites the same keys", () => {
    const keyword = Utils.freeze({
      type: "list",
      data: [
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "a"},
            {type: "integer", value: 1}
          ]
        },
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "b"},
            {type: "integer", value: 2}
          ]
        },
        {
          type: "tuple", 
          data: [
            {type: "atom", value: "a"},
            {type: "integer", value: 9}
          ]
        },
      ]
    })

    const result = Utils.keywordToMap(keyword)

    const expected = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 9},
        "~atom[b]": {type: "integer", value: 2}
      }
    }
    
    assert.deepStrictEqual(result, expected) 
  })

  it("returns freezed object", () => {
    const result = Object.freeze({type: "list", data: []})
    assertFreezed(result)
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
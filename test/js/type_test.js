"use strict";

import { assert, assertFrozen } from "./support/commons";
import Type from "../../assets/js/hologram/type";
import Utils from "../../assets/js/hologram/utils";

describe("atom()", () => {
  it("returns boxed atom value", () => {
    const expected = {type: "atom", value: "test"}
    const result = Type.atom("test")
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.atom("test")
    assertFrozen(result)
  })
})

describe("boolean()", () => {
  it("returns boxed boolean value", () => {
    const expected = {type: "boolean", value: true}
    const result = Type.boolean(true)
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.boolean(true)
    assertFrozen(result)
  })
})

describe("integer()", () => {
  it("returns boxed integer value", () => {
    const expected = {type: "integer", value: 1}
    const result = Type.integer(1)
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.integer(1)
    assertFrozen(result)
  })
})

describe("isFalse()", () => {
  it("returns true for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Type.isFalse(arg)

    assert.isTrue(result)
  })

  it("returns false for boxed true value", () => {
    const arg = {type: "boolean", value: true}
    const result = Type.isFalse(arg)

    assert.isFalse(result)
  })

  it("returns false for values of type other than boxed boolean", () => {
    const arg = {type: "string", value: "false"}
    const result = Type.isFalse(arg)
    
    assert.isFalse(result)
  })
})

describe("isFalsy()", () => {
  it("returns true for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Type.isFalsy(arg)

    assert.isTrue(result)
  })

  it("returns true for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Type.isFalsy(arg)
    
    assert.isTrue(result)
  })

  it("returns false for values other than boxed false or boxed nil values", () => {
    const arg = {type: "integer", value: 0}
    const result = Type.isFalsy(arg)

    assert.isFalse(result)
  })
})

describe("isNil()", () => {
  it("returns true for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Type.isNil(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed nil value", () => {
    const arg = {type: "boolean", value: false}
    const result = Type.isNil(arg)
    
    assert.isFalse(result)
  })
})

describe("isNumber()", () => {
  it("returns true for boxed floats", () => {
    const result = Type.isNumber({type: "float", value: 1.0})
    assert.isTrue(result)
  })

  it("returns true for boxed integers", () => {
    const result = Type.isNumber({type: "integer", value: 1})
    assert.isTrue(result)
  })

  it("returns false for boxed types other than float or integer", () => {
    const result = Type.isNumber({type: "string", value: "1"})
    assert.isFalse(result)
  })
})

describe("isTrue()", () => {
  it("returns true for boxed true value", () => {
    const arg = {type: "boolean", value: true}
    const result = Type.isTrue(arg)

    assert.isTrue(result)
  })

  it("returns false for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Type.isTrue(arg)

    assert.isFalse(result)
  })

  it("returns false for values of types other than boxed boolean", () => {
    const arg = {type: "string", value: "true"}
    const result = Type.isTrue(arg)
    
    assert.isFalse(result)
  })
})

describe("isTruthy()", () => {
  it("returns false for boxed false value", () => {
    const arg = {type: "boolean", value: false}
    const result = Type.isTruthy(arg)

    assert.isFalse(result)
  })

  it("returns false for boxed nil value", () => {
    const arg = {type: "nil"}
    const result = Type.isTruthy(arg)
    
    assert.isFalse(result)
  })

  it("returns true for values other than boxed false or boxed nil values", () => {
    const arg = {type: "integer", value: 0}
    const result = Type.isTruthy(arg)

    assert.isTrue(result)
  })
})

describe("keywordToMap()", () => {
  it("converts empty boxed keyword list to boxed map", () => {
    const keyword = Object.freeze({type: "list", data: []})

    const result = Type.keywordToMap(keyword)
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

    const result = Type.keywordToMap(keyword)

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

    const result = Type.keywordToMap(keyword)

    const expected = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 9},
        "~atom[b]": {type: "integer", value: 2}
      }
    }
    
    assert.deepStrictEqual(result, expected) 
  })

  it("returns frozen object", () => {
    const result = Type.keywordToMap({type: "list", data: []})
    assertFrozen(result)
  })
})

describe("list()", () => {
  it("returns boxed list value", () => {
    const elems = [Type.integer(1), Type.integer(2)]
    const expected = {type: "list", data: elems}
    const result = Type.list(elems)
  
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.list([[Type.integer(1), Type.integer(2)]])
    assertFrozen(result)
  })
})

describe("module()", () => {
  it("returns boxed module value", () => {
    const expected = {type: "module", class_name: "Elixir_ClassStub"}
    const result = Type.module("Elixir_ClassStub")
    assert.deepStrictEqual(result, expected)
  })


  it("returns frozen object", () => {
    const result = Type.module("Elixir_ClassStub")
    assertFrozen(result)
  })
})

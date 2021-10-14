"use strict";

import { assert, assertFrozen } from "./support/commons";
import { HologramNotImplementedError } from "../../assets/js/hologram/errors";
import Type from "../../assets/js/hologram/type";

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

describe("atomKey()", () => {
  it("returns serialized boxed atom value", () => {
    const result = Type.atomKey("test")
    assert.equal(result, "~atom[test]")
  })
})

describe("binary()", () => {
  let elems, result;

  beforeEach(() => {
    elems = [Type.string("abc"), Type.string("xyz")]
    result = Type.binary(elems)
  })

  it("returns boxed binary value", () => {
    const expected = {type: "binary", data: elems}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
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

describe("float()", () => {
  it("returns boxed float value", () => {
    const expected = {type: "float", value: 1.0}
    const result = Type.float(1.0)

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.float(1.0)
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

describe("isAtom()", () => {
  it("returns true for boxed atom value", () => {
    const arg = Type.atom("test")
    const result = Type.isAtom(arg)

    assert.isTrue(result)
  })

  it("returns false for values of type other than boxed atom", () => {
    const arg = Type.boolean(false)
    const result = Type.isAtom(arg)
    
    assert.isFalse(result)
  })
})

describe("isFalse()", () => {
  it("returns true for boxed false value", () => {
    const arg = Type.boolean(false)
    const result = Type.isFalse(arg)

    assert.isTrue(result)
  })

  it("returns false for boxed true value", () => {
    const arg = Type.boolean(true)
    const result = Type.isFalse(arg)

    assert.isFalse(result)
  })

  it("returns false for values of type other than boxed boolean", () => {
    const arg = Type.string("false")
    const result = Type.isFalse(arg)
    
    assert.isFalse(result)
  })
})

describe("isFalsy()", () => {
  it("returns true for boxed false value", () => {
    const arg = Type.boolean(false)
    const result = Type.isFalsy(arg)

    assert.isTrue(result)
  })

  it("returns true for boxed nil value", () => {
    const arg = Type.nil()
    const result = Type.isFalsy(arg)
    
    assert.isTrue(result)
  })

  it("returns false for values other than boxed false or boxed nil values", () => {
    const arg = Type.integer(0)
    const result = Type.isFalsy(arg)

    assert.isFalse(result)
  })
})

describe("isList()", () => {
  it("returns true for boxed list value", () => {
    const arg = Type.list([])
    const result = Type.isList(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed list value", () => {
    const arg = Type.boolean(false)
    const result = Type.isList(arg)
    
    assert.isFalse(result)
  })
})

describe("isMap()", () => {
  it("returns true for boxed map value", () => {
    const arg = Type.map({})
    const result = Type.isMap(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed map value", () => {
    const arg = Type.boolean(false)
    const result = Type.isMap(arg)
    
    assert.isFalse(result)
  })
})

describe("isNil()", () => {
  it("returns true for boxed nil value", () => {
    const arg = Type.nil()
    const result = Type.isNil(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed nil value", () => {
    const arg = Type.boolean(false)
    const result = Type.isNil(arg)
    
    assert.isFalse(result)
  })
})

describe("isNumber()", () => {
  it("returns true for boxed floats", () => {
    const arg = Type.float(1.0)
    const result = Type.isNumber(arg)

    assert.isTrue(result)
  })

  it("returns true for boxed integers", () => {
    const arg = Type.integer(1)
    const result = Type.isNumber(arg)

    assert.isTrue(result)
  })

  it("returns false for boxed types other than float or integer", () => {
    const arg = Type.string("1")
    const result = Type.isNumber(arg)

    assert.isFalse(result)
  })
})

describe("isString()", () => {
  it("returns true for boxed string value", () => {
    const arg = Type.string("test")
    const result = Type.isString(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed string value", () => {
    const arg = Type.boolean(false)
    const result = Type.isString(arg)
    
    assert.isFalse(result)
  })
})

describe("isTrue()", () => {
  it("returns true for boxed true value", () => {
    const arg = Type.boolean(true)
    const result = Type.isTrue(arg)

    assert.isTrue(result)
  })

  it("returns false for boxed false value", () => {
    const arg = Type.boolean(false)
    const result = Type.isTrue(arg)

    assert.isFalse(result)
  })

  it("returns false for values of types other than boxed boolean", () => {
    const arg = Type.string("true")
    const result = Type.isTrue(arg)
    
    assert.isFalse(result)
  })
})

describe("isTruthy()", () => {
  it("returns false for boxed false value", () => {
    const arg = Type.boolean(false)
    const result = Type.isTruthy(arg)

    assert.isFalse(result)
  })

  it("returns false for boxed nil value", () => {
    const arg = Type.nil()
    const result = Type.isTruthy(arg)
    
    assert.isFalse(result)
  })

  it("returns true for values other than boxed false or boxed nil values", () => {
    const arg = Type.integer(0)
    const result = Type.isTruthy(arg)

    assert.isTrue(result)
  })
})

describe("isTuple()", () => {
  it("returns true for boxed tuple value", () => {
    const arg = Type.tuple([])
    const result = Type.isTuple(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed tuple value", () => {
    const arg = Type.boolean(false)
    const result = Type.isTuple(arg)
    
    assert.isFalse(result)
  })
})

describe("keywordToMap()", () => {
  it("converts empty boxed keyword list to boxed map", () => {
    const keyword = Type.list([])
    const result = Type.keywordToMap(keyword)
    const expected = Type.map({})
    
    assert.deepStrictEqual(result, expected) 
  })

  it("converts non-empty boxed keyword list to boxed map ", () => {
    const keywordElems = [
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)])
    ]

    const keyword = Type.list(keywordElems)
    const result = Type.keywordToMap(keyword)

    const mapElems = {}
    mapElems[Type.atomKey("a")] = Type.integer(1)
    mapElems[Type.atomKey("b")] = Type.integer(2)
    const expected = Type.map(mapElems)
    
    assert.deepStrictEqual(result, expected) 
  })

  it("overwrites the same keys", () => {
    const keywordElems = [
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.tuple([Type.atom("a"), Type.integer(9)])
    ]

    const keyword = Type.list(keywordElems)
    const result = Type.keywordToMap(keyword)

    const mapElems = {}
    mapElems[Type.atomKey("a")] = Type.integer(9)
    mapElems[Type.atomKey("b")] = Type.integer(2)
    const expected = Type.map(mapElems)
    
    assert.deepStrictEqual(result, expected) 
  })

  it("returns frozen object", () => {
    const arg = Type.list([])
    const result = Type.keywordToMap(arg)

    assertFrozen(result)
  })
})

describe("list()", () => {
  let elems, expected, result;

  beforeEach(() => {
    elems = [Type.integer(1), Type.integer(2)]
    expected = {type: "list", data: elems}
    result = Type.list(elems)
  })

  it("returns boxed list value", () => {
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("map()", () => {
  let elems, result;

  beforeEach(() => {
    elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    result = Type.map(elems)
  })

  it("returns boxed map value", () => {
    const expected = {type: "map", data: elems}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("module()", () => {
  it("returns boxed module value", () => {
    const expected = {type: "module", className: "Elixir_ClassStub"}
    const result = Type.module("Elixir_ClassStub")

    assert.deepStrictEqual(result, expected)
  })


  it("returns frozen object", () => {
    const result = Type.module("Elixir_ClassStub")
    assertFrozen(result)
  })
})

describe("nil()", () => {
  it("returns boxed nil value", () => {
    const expected = {type: "nil"}
    const result = Type.nil()

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.nil()
    assertFrozen(result)
  })
})

describe("placeholder()", () => {
  it("returns boxed placeholder value", () => {
    const expected = {type: "placeholder"}
    const result = Type.placeholder()

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.placeholder()
    assertFrozen(result)
  })
})

describe("serializedKey()", () => {
  it("serializes boxed atom value for use as a boxed map key", () => {
    const arg = Type.atom("test")
    const result = Type.serializedKey(arg)

    assert.match(result, /atom/)
  })

  it("serializes boxed string value for use as a boxed map key", () => {
    const arg = Type.string("test")
    const result = Type.serializedKey(arg)

    assert.match(result, /string/)
  })

  it("throws an error for not implemented types", () => {
    const arg = {type: "not implemented", value: "test"}
    const expectedMessage = 'Type.serializedKey(): boxedValue = {"type":"not implemented","value":"test"}'
    
    assert.throw(() => { Type.serializedKey(arg) }, HologramNotImplementedError, expectedMessage);
  })
})

describe("string()", () => {
  it("returns boxed string value", () => {
    const expected = {type: "string", value: "test"}
    const result = Type.string("test")

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.string("test")
    assertFrozen(result)
  })
})

describe("stringKey()", () => {
  it("returns serialized boxed string value", () => {
    const result = Type.stringKey("test")
    assert.equal(result, "~string[test]")
  })
})

describe("textNode()", () => {
  it("builds a text node", () => {
    const expected = {type: "text", content: "test"}
    const result = Type.textNode("test")

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const result = Type.textNode("test")
    assertFrozen(result)
  })
})

describe("tuple()", () => {
  let elems, expected, result;

  beforeEach(() => {
    elems = [Type.integer(1), Type.integer(2)]
    expected = {type: "tuple", data: elems}
    result = Type.tuple(elems)
  })

  it("returns boxed tuple value", () => {
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})
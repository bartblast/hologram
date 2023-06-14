"use strict";

import { assert, assertFrozen, assertNotFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import { HologramNotImplementedError } from "../../assets/js/hologram/errors";
import Type from "../../assets/js/hologram/type";


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

describe("componentNode()", () => {
  const result = Type.componentNode("test_class_name", "test_props", "test_children")

  it("builds a component node", () => {
    const expected = {type: "component", className: "test_class_name", props: "test_props", children: "test_children"}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("consOperatorPattern()", () => {
  let head, tail, result;

  beforeEach(() => {
    head = Type.integer(1)
    tail = Type.list([Type.integer(2), Type.integer(3)])
    
    result = Type.consOperatorPattern(head, tail)
  })

  it("returns boxed cons_operator_pattern value", () => {
    const expected = {type: "cons_operator_pattern", head: head, tail: tail}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("decodeKey()", () => {
  it("decodes encoded atom key", () => {
    const boxedValue = Type.atom("test")
    const encodedKey = Type.encodedKey(boxedValue)

    const result = Type.decodeKey(encodedKey)
    assert.deepStrictEqual(result, boxedValue)
  })

  it("decodes encoded string key", () => {
    const boxedValue = Type.string("test")
    const encodedKey = Type.encodedKey(boxedValue)

    const result = Type.decodeKey(encodedKey)
    assert.deepStrictEqual(result, boxedValue)
  })

  it("throws an error for not implemented types", () => {
    const arg = "~invalid[123]"
    const expectedMessage = 'Type.decodeKey(): key = "~invalid[123]"'
    
    assert.throw(() => { Type.decodeKey(arg) }, HologramNotImplementedError, expectedMessage);
  })

  it("returns frozen object", () => {
    const result = Type.decodeKey(Type.atomKey("test"))
    assertFrozen(result)
  })
})

describe("elementNode()", () => {
  const result = Type.elementNode("div", "test_attrs", "test_children")

  it("builds an element node", () => {
    const expected = {type: "element", tag: "div", attrs: "test_attrs", children: "test_children"}
    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("encodedKey()", () => {
  it("serializes boxed atom value for use as a boxed map key", () => {
    const arg = Type.atom("test")
    const result = Type.encodedKey(arg)

    assert.match(result, /atom/)
  })

  it("serializes boxed string value for use as a boxed map key", () => {
    const arg = Type.string("test")
    const result = Type.encodedKey(arg)

    assert.match(result, /string/)
  })

  it("throws an error for not implemented types", () => {
    const arg = {type: "not implemented", value: "test"}
    const expectedMessage = 'Type.encodedKey(): boxedValue = {"type":"not implemented","value":"test"}'
    
    assert.throw(() => { Type.encodedKey(arg) }, HologramNotImplementedError, expectedMessage);
  })
})

describe("isExpressionNode()", () => {
  it("returns true if the arg is an expression node", () => {
    const arg = Type.expressionNode("test_callback")
    const result = Type.isExpressionNode(arg)

    assert.isTrue(result)
  })

  it("returns false if the arg is not an expression node", () => {
    const arg = Type.textNode("test_content")
    const result = Type.isExpressionNode(arg)
    
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
    const arg = Type.list()
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
    const arg = Type.map()
    const result = Type.isMap(arg)

    assert.isTrue(result)
  })

  it("returns false for values other than boxed map value", () => {
    const arg = Type.boolean(false)
    const result = Type.isMap(arg)
    
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
    const arg = Type.tuple()
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
    const keyword = Type.list()
    const result = Type.keywordToMap(keyword)
    const expected = Type.map()
    
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
    const arg = Type.list()
    const result = Type.keywordToMap(arg)

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

  it("returns immutable object by default", () => {
    assertFrozen(result)
  })

  it("returns mutable object if immutable arg is set to false", () => {
    result = Type.map(elems, false)
    assertNotFrozen(result)
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

describe("stringKey()", () => {
  it("returns serialized boxed string value", () => {
    const result = Type.stringKey("test")
    assert.equal(result, "~string[test]")
  })
})

describe("struct()", () => {
  let elems, result;

  beforeEach(() => {
    elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    result = Type.struct("TestClass", elems)
  })

  it("returns boxed map value", () => {
    const expected = {type: "struct", className: "TestClass", data: elems}
    assert.deepStrictEqual(result, expected)
  })

  it("returns immutable object", () => {
    assertFrozen(result)
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
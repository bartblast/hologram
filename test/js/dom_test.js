"use strict";

import { assert, assertFrozen } from "./support/commons";
import DOM from "../../assets/js/hologram/dom";
import { HologramNotImplementedError } from "../../assets/js/hologram/errors"
import SpecialForms from "../../assets/js/hologram/elixir/kernel/special_forms";
import Type from "../../assets/js/hologram/type";

describe("buildTextVNode()", () => {
  it("builds text vnode", () => {
    const textNode = Type.textNode("test")
    const result = DOM.buildTextVNode(textNode)

    assert.deepStrictEqual(result, ["test"])
  })
})

describe("buildVNodeEventHandlers()", () => {
  it("builds click event handler", () => {
    const attrs = {on_click: "test_on_click_spec"}
    const elementNode = Type.elementNode("div", attrs, [])
    const result = DOM.buildVNodeEventHandlers(elementNode)

    assert.isFunction(result.click)
  })
})

describe("evaluateNode()", () => {
  it("evaluates expression node", () => {
    const elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)

    const bindings = Type.map(elems)
    const key = Type.atom("a")
    const callback = ($bindings) => { return Type.tuple([SpecialForms.$dot($bindings, key)])}

    const expressionNode = Type.expressionNode(callback)

    const result = DOM.evaluateNode(expressionNode, bindings)
    const expected = Type.integer(1)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })

  it("evaluates text node", () => {
    const bindings = Type.map({})
    const textNode = Type.textNode("test_content")

    const result = DOM.evaluateNode(textNode, bindings)
    const expected = Type.string("test_content")

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("interpolate()", () => {
  it("interpolates boxed atom value", () => {
    const value = Type.atom("abc")
    const result = DOM.interpolate(value)

    assert.equal(result, "abc")
  })

  it("interpolates boxed boolean value", () => {
    const value = Type.boolean(true)
    const result = DOM.interpolate(value)

    assert.equal(result, "true")
  })

  it("interpolates boxed integer value", () => {
    const value = Type.integer(1)
    const result = DOM.interpolate(value)

    assert.equal(result, "1")
  })

  it("interpolates boxed string value", () => {
    const value = Type.string("abc")
    const result = DOM.interpolate(value)

    assert.equal(result, "abc")
  })

  it("interpolates boxed binary value", () => {
    const value = Type.binary([Type.string("abc"), Type.string("xyz")])
    const result = DOM.interpolate(value)

    assert.equal(result, "abcxyz")
  })

  it("interpolates boxed nil value", () => {
    const value = Type.nil()
    const result = DOM.interpolate(value)

    assert.equal(result, "")
  })

  it("throws an error for not implemented types", () => {
    const value = {type: "not implemented", value: "test"}
    const expectedMessage = 'DOM.interpolate(): value = {"type":"not implemented","value":"test"}'

    assert.throw(() => { DOM.interpolate(value) }, HologramNotImplementedError, expectedMessage);
  })
})
"use strict";

import { assert } from "./support/commons";
import DOM from "../../assets/js/hologram/dom";
import { HologramNotImplementedError } from "../../assets/js/hologram/errors"
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
"use strict";

import { assert, assertFrozen } from "./support/commons";
import DOM from "../../assets/js/hologram/dom";
import { HologramNotImplementedError } from "../../assets/js/hologram/errors"
import Operation from "../../assets/js/hologram/operation";
import SpecialForms from "../../assets/js/hologram/elixir/kernel/special_forms";
import Type from "../../assets/js/hologram/type";
import Store from "../../assets/js/hologram/store";

const elems = {}
elems[Type.atomKey("a")] = Type.integer(1)

const bindings = Type.map(elems)
const key = Type.atom("a")
const callback = ($bindings) => { return Type.tuple([SpecialForms.$dot($bindings, key)])}

describe("aggregateComponentBindings()", () => {
  it("aggregates component bindings", () => {
    const outerBindingsElems = {}
    outerBindingsElems[Type.atomKey("context")] = Type.string("text_context_value")
    outerBindingsElems[Type.atomKey("a")] = Type.integer(1)
    outerBindingsElems[Type.atomKey("x")] = Type.string("x_value")
    const outerBindings = Type.map(outerBindingsElems)

    const stateElems = {}
    stateElems[Type.atomKey("k")] = Type.string("value_2")
    stateElems[Type.atomKey("y")] = Type.string("y_value")
    const state = Type.map(stateElems)
    Store.setComponentState("test_id", state)

    const props = {
      id: [Type.textNode("test_id")],
      k: [Type.textNode("value_1")],
      b: [Type.expressionNode(callback)]
    }

    const componentNode = Type.componentNode("test_class_name", props, [])

    const result = DOM.aggregateComponentBindings(componentNode, outerBindings)

    const expectedElems = {}
    expectedElems[Type.atomKey("context")] = Type.string("text_context_value")
    expectedElems[Type.atomKey("id")] = Type.string("test_id")
    expectedElems[Type.atomKey("k")] = Type.string("value_2")
    expectedElems[Type.atomKey("b")] = Type.integer(1)
    expectedElems[Type.atomKey("y")] = Type.string("y_value")
    const expected = Type.map(expectedElems)

    assert.deepStrictEqual(result, expected)
  })
})

describe("aggregateComponentContextBindings()", () => {
  it("aggregates component context bindings", () => {
    const outerBindingsElems = {}
    outerBindingsElems[Type.atomKey("xyz")] = Type.integer(9)
    outerBindingsElems[Type.atomKey("context")] = Type.string("text_context_value")
    const outerBindings = Type.map(outerBindingsElems)

    const result = DOM.aggregateComponentContextBindings(outerBindings)

    const expectedElems = {}
    expectedElems[Type.atomKey("context")] = Type.string("text_context_value")
    const expected = Type.map(expectedElems)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("aggregateComponentPropsBindings()", () => {
  it("aggregates component props bindings", () => {
    const props = {
      id: [Type.textNode("test_id")],
      value: [Type.expressionNode(callback)]
    }

    const componentNode = Type.componentNode("test_class_name", props, [])

    const result = DOM.aggregateComponentPropsBindings(componentNode, bindings)

    const elems = {}
    elems[Type.atomKey("id")] = Type.string("test_id")
    elems[Type.atomKey("value")] = Type.integer(1)
    const expected = Type.map(elems)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("aggregateComponentStateBindings()", () => {
  it("returns state bindings of a stateful component", () => {
    const elems = {}
    elems[Type.atomKey("x")] = Type.integer(9)
    const state = Type.map(elems)

    Store.setComponentState("test_id", state)

    const props = {
      id: [Type.textNode("test_id")]
    }

    const node = Type.componentNode("test_class_name", props, [])
    const result = DOM.aggregateComponentStateBindings(node, bindings)

    assert.deepStrictEqual(result, state)
    assertFrozen(result)
  })

  it("returns empty JS object if the component is stateless", () => {
    const node = Type.componentNode("test_class_name", {}, [])
    const result = DOM.aggregateComponentStateBindings(node, bindings)

    assert.deepStrictEqual(result, {})
    assertFrozen(result)
  })
})

describe("buildElementVNode()", () => {
  const source = Operation.TARGET.page

  it("builds tag element vnode", () => {
    const attrs = {
      abc: {
        value: [Type.textNode("valueAbc")],
        modifiers: []
      },
      on_click: "test_on_click_spec"
    }

    const children = [Type.textNode("childTextNode")]
    const node = Type.elementNode("div", attrs, children)

    const result = DOM.buildElementVNode(node, source, bindings, {})
    const clickHandler = result[0].data.on.click

    const expected = [{
      sel: "div",
      data: {
        attrs: {
          abc: "valueAbc"
        },
        on: {
          click: clickHandler
        } 
      },
      children: [{
        children: undefined,
        data: undefined,
        elm: undefined,
        key: undefined,
        sel: undefined,
        text: "childTextNode"
      }],
      text: undefined,
      elm: undefined,
      key: undefined
    }]

    assert.isFunction(clickHandler)
    assert.deepStrictEqual(result, expected)
  })

  it("builds slot vnodes", () => {
    const node = Type.elementNode("slot", {}, [])

    const slots = {
      default: [Type.textNode("test_text_node")]
    }

    const result = DOM.buildElementVNode(node, source, bindings, slots)
    const expected = ["test_text_node"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildTextVNodeFromTextNode()", () => {
  it("builds text vnode from text node", () => {
    const textNode = Type.textNode("test")
    const result = DOM.buildTextVNodeFromTextNode(textNode)

    assert.deepStrictEqual(result, ["test"])
  })
})

describe("buildTextVNodeFromExpression()", () => {
  it("evaluates expression node and interpolates the result to a text vnode", () => {
    const node = Type.expressionNode(callback)

    const result = DOM.buildTextVNodeFromExpression(node, bindings)
    const expected = ["1"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildVNodeAttrs()", () => {
  it("builds vnode attributes", () => {
    const node = {
      attrs: {
        abc: {
          value: [Type.textNode("valueAbc")],
          modifiers: [] 
        },
        xyz: {
          value: [Type.expressionNode(callback)],
          modifiers: []
        }
      }
    }

    const result = DOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: "valueAbc", xyz: "1"}

    assert.deepStrictEqual(result, expected)
  })

  it("doesn't include on:(event) attributes", () => {
    const node = {
      attrs: {
        on_click: {
          value: [Type.textNode("valueOnClick")],
          modifiers: [] 
        }
      }
    }

    const result = DOM.buildVNodeAttrs(node, bindings)

    assert.deepStrictEqual(result, {})
  })
})

describe("buildVNodeEventHandlers()", () => {
  it("builds vnode click event handler", () => {
    const attrs = {on_click: "test_on_click_spec"}
    const elementNode = Type.elementNode("div", attrs, [])
    const result = DOM.buildVNodeEventHandlers(elementNode)

    assert.isFunction(result.click)
  })
})

describe("buildVNodeList()", () => {
  it("builds a list of vnodes", () => {
    const nodes = [Type.textNode("node1"), Type.textNode("node2")]

    const result = DOM.buildVNodeList(nodes, Operation.TARGET.page, bindings, {})
    const expected = ["node1", "node2"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("evaluateAttr()", () => {
  it("evaluates attribute value to a string", () => {
    const nodes = [
      Type.textNode("abc"),
      Type.expressionNode(callback)
    ]

    const result = DOM.evaluateAttr(nodes, bindings)

    assert.equal(result, "abc1")
  })
})

describe("evaluateNode()", () => {
  it("evaluates expression node to a boxed value", () => {
    const expressionNode = Type.expressionNode(callback)

    const result = DOM.evaluateNode(expressionNode, bindings)
    const expected = Type.integer(1)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })

  it("evaluates text node to a boxed value", () => {
    const bindings = Type.map({})
    const textNode = Type.textNode("test_content")

    const result = DOM.evaluateNode(textNode, bindings)
    const expected = Type.string("test_content")

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("evaluateProp()", () => {
  it("evaluates the prop value to a boxed string when the value is composed of one value node only", () => {
    const nodes = [Type.textNode("test_text_node")]

    const result = DOM.evaluateProp(nodes, bindings)
    const expected = Type.string("test_text_node")

    assert.deepStrictEqual(result, expected)
  })

  it("evaluates the prop value to a boxed string when the value is composed of multiple value nodes", () => {
    const nodes = [
      Type.textNode("test_text_node"),
      Type.expressionNode(callback)
    ]

    const result = DOM.evaluateProp(nodes, bindings)
    const expected = Type.string("test_text_node1")

    assert.deepStrictEqual(result, expected)
  })
})

describe("getComponentId()", () => {
  it("returns component id prop as JS string", () => {
    const props = {
      id: [
        Type.textNode("test"),
        Type.expressionNode(callback)
      ]
    }

    const node = Type.componentNode("test_class_name", props, [])
    const result = DOM.getComponentId(node, bindings)

    assert.equal(result, "test1")
  })
})

describe("interpolate()", () => {
  it("converts boxed atom value to JS string", () => {
    const value = Type.atom("abc")
    const result = DOM.interpolate(value)

    assert.equal(result, "abc")
  })

  it("converts boxed boolean value to JS string", () => {
    const value = Type.boolean(true)
    const result = DOM.interpolate(value)

    assert.equal(result, "true")
  })

  it("converts boxed integer value to JS string", () => {
    const value = Type.integer(1)
    const result = DOM.interpolate(value)

    assert.equal(result, "1")
  })

  it("converts boxed string value to JS string", () => {
    const value = Type.string("abc")
    const result = DOM.interpolate(value)

    assert.equal(result, "abc")
  })

  it("converts boxed binary value to JS string", () => {
    const value = Type.binary([Type.string("abc"), Type.string("xyz")])
    const result = DOM.interpolate(value)

    assert.equal(result, "abcxyz")
  })

  it("converts boxed nil value to JS string", () => {
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

describe("isStatefulComponent()", () => {
  const TestComponent = class {}

  it("returns true if the given component has 'id' prop", () => {
    const props = {
      id: [Type.textNode("test_id")]
    }
    
    const node = Type.componentNode(TestComponent, props, [])
    const result = DOM.isStatefulComponent(node)

    assert.isTrue(result)
  })

  it("returns false if the given component doesn't have 'id' prop", () => {
    const props = {
      test_prop: [Type.textNode("test_value")]
    }

    const node = Type.componentNode(TestComponent, props, [])
    const result = DOM.isStatefulComponent(node)

    assert.isFalse(result)
  })
})
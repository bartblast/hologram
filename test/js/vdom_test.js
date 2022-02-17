"use strict";

import { assert, assertFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import SpecialForms from "../../assets/js/hologram/elixir/kernel/special_forms";
import Target from "../../assets/js/hologram/target";
import Type from "../../assets/js/hologram/type";
import Store from "../../assets/js/hologram/store";
import VDOM from "../../assets/js/hologram/vdom";

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

    const result = VDOM.aggregateComponentBindings("test_id", componentNode, outerBindings)

    const expectedElems = {}
    expectedElems[Type.atomKey("context")] = Type.string("text_context_value")
    expectedElems[Type.atomKey("id")] = Type.string("test_id")
    expectedElems[Type.atomKey("k")] = Type.string("value_2")
    expectedElems[Type.atomKey("b")] = Type.integer(1)
    expectedElems[Type.atomKey("y")] = Type.string("y_value")
    const expected = Type.map(expectedElems)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("aggregateComponentContextBindings()", () => {
  it("aggregates component context bindings", () => {
    const outerBindingsElems = {}
    outerBindingsElems[Type.atomKey("xyz")] = Type.integer(9)
    outerBindingsElems[Type.atomKey("context")] = Type.string("text_context_value")
    const outerBindings = Type.map(outerBindingsElems)

    const result = VDOM.aggregateComponentContextBindings(outerBindings)

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

    const result = VDOM.aggregateComponentPropsBindings(componentNode, bindings)

    const elems = {}
    elems[Type.atomKey("id")] = Type.string("test_id")
    elems[Type.atomKey("value")] = Type.integer(1)
    const expected = Type.map(elems)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("aggregateLayoutBindings()", () => {
  it("aggregates layout bindings", () => {
    let pageStateElems = {}
    pageStateElems[Type.atomKey("a")] = Type.integer(1)
    pageStateElems[Type.atomKey("b")] = Type.integer(2)
    const pageState = Type.map(pageStateElems)

    let layoutStateElems = {}
    layoutStateElems[Type.atomKey("b")] = Type.integer(3)
    layoutStateElems[Type.atomKey("c")] = Type.integer(4)
    const layoutState = Type.map(layoutStateElems)

    Store.setComponentState(Target.TYPE.page, pageState)
    Store.setComponentState(Target.TYPE.layout, layoutState)

    const result = VDOM.aggregateLayoutBindings()

    const expectedElems = {}
    expectedElems[Type.atomKey("a")] = Type.integer(1)
    expectedElems[Type.atomKey("b")] = Type.integer(3)
    expectedElems[Type.atomKey("c")] = Type.integer(4)
    const expected = Type.map(expectedElems)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })
})

describe("buildComponentVNodes()", () => {
  it("builds stateless component's vnodes", () => {
    const TestStatelessComponent = class {
      static template() {
        return [
          Type.textNode("text_node_1"),
          Type.elementNode("slot", {}, []),
          Type.textNode("text_node_2")
        ]
      }
    }
    globalThis.TestStatelessComponent = TestStatelessComponent

    const children = [Type.textNode("text_node_3")]
    const node = Type.componentNode("TestStatelessComponent", {}, children)

    const result = VDOM.buildComponentVNodes(node, "test_sourceId", Type.map()) 
    const expected = ["text_node_1", "text_node_3", "text_node_2"]

    assert.deepStrictEqual(result, expected)
  })

  it("builds stateful component's vnodes", () => {
    const TestStatefulComponent = class {
      static template() {
        return [
          Type.textNode("text_node_1"),
          Type.elementNode("slot", {}, []),
          Type.textNode("text_node_2")
        ]
      }
    }
    globalThis.TestStatefulComponent = TestStatefulComponent

    const props = {id: [Type.textNode("test_component_id")]}
    const children = [Type.expressionNode(callback)]
    const node = Type.componentNode("TestStatefulComponent", props, children)

    const elems = {}
    elems[Type.atomKey("a")] = Type.integer(99)
    Store.setComponentState("test_component_id", Type.map(elems))

    const result = VDOM.buildComponentVNodes(node, "test_sourceId", Type.map()) 
    const expected = ["text_node_1", "99", "text_node_2"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildElementVNode()", () => {
  const sourceId = Target.TYPE.page

  it("builds tag element vnode", () => {
    const attrs = {
      abc: {
        value: [Type.textNode("valueAbc")],
        modifiers: []
      },
      "on:click": "test_on_click_spec"
    }

    const children = [Type.textNode("childTextNode")]
    const node = Type.elementNode("div", attrs, children)

    const result = VDOM.buildElementVNode(node, sourceId, bindings, {})
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

    const result = VDOM.buildElementVNode(node, sourceId, bindings, slots)
    const expected = ["test_text_node"]

    assert.deepStrictEqual(result, expected)
  })

  it("handles the 'if' directive", () => {
    const attrs = {
      if: {
        modifiers: [],
        value: [Type.expressionNode(() => {
          return Type.tuple([Type.nil()])
        })]
      }
    }

    const node = Type.elementNode("div", attrs)
    const bindings = Type.map()
    const result = VDOM.buildElementVNode(node, "test-source-id", bindings, {})

    assert.deepStrictEqual(result, [])
  })

  // Covered implicitely in E2E tests.
  // it("changes the sourceId to page if the current sourceId is layout and the current tag is a slot")
  // it("loads page bindings if the current sourceId is layout and the current tag is a slot")
})

describe("buildTextVNodeFromTextNode()", () => {
  it("builds text vnode from text node", () => {
    const textNode = Type.textNode("test")
    const result = VDOM.buildTextVNodeFromTextNode(textNode)

    assert.deepStrictEqual(result, ["test"])
  })
})

describe("buildTextVNodeFromExpression()", () => {
  it("evaluates expression node and interpolates the result to a text vnode", () => {
    const node = Type.expressionNode(callback)

    const result = VDOM.buildTextVNodeFromExpression(node, bindings)
    const expected = ["1"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildVNodeAttrs()", () => {
  it("builds literal attribute", () => {
    const node = {
      attrs: {
        abc: {
          value: [Type.textNode("valueAbc")],
          modifiers: [] 
        },
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: "valueAbc"}

    assert.deepStrictEqual(result, expected)
  })

  it("builds expression attribute", () => {
    const node = {
      attrs: {
        abc: {
          value: [Type.expressionNode(callback)],
          modifiers: []
        }
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: "1"}

    assert.deepStrictEqual(result, expected)
  })

  it("builds boolean attribute", () => {
    const node = {
      attrs: {
        abc: {
          value: null,
          modifiers: []
        }
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: true}

    assert.deepStrictEqual(result, expected)
  })

  it("builds expression attribute which evaluates to nil", () => {
    const callback = ($) => { return Type.tuple([Type.nil()]) }

    const node = {
      attrs: {
        abc: {
          value: [Type.expressionNode(callback)],
          modifiers: []
        }
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: true}

    assert.deepStrictEqual(result, expected)
  })

  it("doesn't build expression attribute which evaluates to false", () => {
    const callback = ($) => { return Type.tuple([Type.boolean(false)]) }

    const node = {
      attrs: {
        abc: {
          value: [Type.expressionNode(callback)],
          modifiers: []
        }
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {}

    assert.deepStrictEqual(result, expected)
  })

  it("builds multiple attributes", () => {
    const node = {
      attrs: {
        abc: {
          value: [Type.textNode("valueAbc")],
          modifiers: [] 
        },
        xyz: {
          value: [Type.textNode("valueXyz")],
          modifiers: [] 
        },
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)
    const expected = {abc: "valueAbc", xyz: "valueXyz"}

    assert.deepStrictEqual(result, expected)
  })

  it("doesn't include on:(event) attributes", () => {
    const node = {
      attrs: {
        "on:click": {
          value: [Type.textNode("valueOnClick")],
          modifiers: [] 
        }
      }
    }

    const result = VDOM.buildVNodeAttrs(node, bindings)

    assert.deepStrictEqual(result, {})
  })
})

describe("buildVNodeEventHandlers()", () => {
  it("builds vnode change event handler", () => {
    const attrs = {"on:change": "test_on_change_spec"}
    const elementNode = Type.elementNode("form", attrs, [])
    const result = VDOM.buildVNodeEventHandlers(elementNode)

    assert.isFunction(result.change)
  })

  it("builds vnode click event handler", () => {
    const attrs = {"on:click": "test_on_click_spec"}
    const elementNode = Type.elementNode("div", attrs, [])
    const result = VDOM.buildVNodeEventHandlers(elementNode)

    assert.isFunction(result.click)
  })

  it("builds vnode submit event handler", () => {
    const attrs = {"on:submit": "test_on_submit_spec"}
    const elementNode = Type.elementNode("form", attrs, [])
    const result = VDOM.buildVNodeEventHandlers(elementNode)

    assert.isFunction(result.submit)
  })
})

describe("buildVNodeList()", () => {
  it("converts expression nodes into text nodes", () => {
    const nodes = [Type.expressionNode(callback)]

    const result = VDOM.buildVNodeList(nodes, Target.TYPE.page, bindings, {})
    const expected = ["1"]

    assert.deepStrictEqual(result, expected)
  })

  it("merges consecutive text nodes", () => {
    const nodes = [Type.textNode("abc"), Type.expressionNode(callback), Type.textNode("xyz")]

    const result = VDOM.buildVNodeList(nodes, Target.TYPE.page, bindings, {})
    const expected = ["abc1xyz"]

    assert.deepStrictEqual(result, expected)
  })
})

describe("evaluateAttrParts()", () => {
  it("evaluates attribute parts", () => {
    const nodes = [
      Type.textNode("abc"),
      Type.expressionNode(callback)
    ]

    const result = VDOM.evaluateAttrParts(nodes, bindings)
    const expected = [Type.string("abc"), Type.integer(1)]

    assert.deepStrictEqual(result, expected)
  })
})

describe("evaluateNode()", () => {
  it("evaluates expression node to a boxed value", () => {
    const expressionNode = Type.expressionNode(callback)

    const result = VDOM.evaluateNode(expressionNode, bindings)
    const expected = Type.integer(1)

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })

  it("evaluates text node to a boxed value", () => {
    const bindings = Type.map()
    const textNode = Type.textNode("test_content")

    const result = VDOM.evaluateNode(textNode, bindings)
    const expected = Type.string("test_content")

    assert.deepStrictEqual(result, expected)
    assertFrozen(result)
  })

  // DEFER: test
  // it("injects bindings key to bindings", () => {})
})

describe("evaluateProp()", () => {
  it("evaluates the prop value to a boxed string when the value is composed of one value node only", () => {
    const nodes = [Type.textNode("test_text_node")]

    const result = VDOM.evaluateProp(nodes, bindings)
    const expected = Type.string("test_text_node")

    assert.deepStrictEqual(result, expected)
  })

  it("evaluates the prop value to a boxed string when the value is composed of multiple value nodes", () => {
    const nodes = [
      Type.textNode("test_text_node"),
      Type.expressionNode(callback)
    ]

    const result = VDOM.evaluateProp(nodes, bindings)
    const expected = Type.string("test_text_node1")

    assert.deepStrictEqual(result, expected)
  })
})

describe("evaluateAttrToString()", () => {
  it("interpolates and joins parts of attribute value", () => {
    const nodes = [
      Type.string("abc"),
      Type.integer(1),
      Type.string("xyz")
    ]

    const result = VDOM.evaluateAttrToString(nodes, bindings)

    assert.deepStrictEqual(result, "abc1xyz")
  })
})

describe("getComponentId()", () => {
  it("returns component ID prop as JS string if the component is stateful", () => {
    const props = {
      id: [
        Type.textNode("test"),
        Type.expressionNode(callback)
      ]
    }

    const node = Type.componentNode("test_class_name", props, [])
    const result = VDOM.getComponentId(node, bindings)

    assert.equal(result, "test1")
  })

  it("returns null if the component is stateless", () => {
    const node = Type.componentNode("test_class_name", {}, [])
    const result = VDOM.getComponentId(node, bindings)

    assert.isNull(result)
  })
})

describe("interpolate()", () => {
  it("converts a boxed list to JS string", () => {
    const value = Type.list([Type.integer(1), Type.integer(2)])
    const result = VDOM.interpolate(value)

    assert.equal(result, "[1, 2]")
  })

  it("converts a non-string boxed value to JS string", () => {
    const value = Type.atom("abc")
    const result = VDOM.interpolate(value)

    assert.equal(result, "abc")
  })
})

describe("isStatefulComponent()", () => {
  const TestComponent = class {}

  it("returns true if the given component has 'id' prop", () => {
    const props = {
      id: [Type.textNode("test_id")]
    }
    
    const node = Type.componentNode(TestComponent, props, [])
    const result = VDOM.isStatefulComponent(node)

    assert.isTrue(result)
  })

  it("returns false if the given component doesn't have 'id' prop", () => {
    const props = {
      test_prop: [Type.textNode("test_value")]
    }

    const node = Type.componentNode(TestComponent, props, [])
    const result = VDOM.isStatefulComponent(node)

    assert.isFalse(result)
  })
})

describe("reset()", () => {
  it("sets the virtualDocument field to null", () => {
    VDOM.virtualDocument = "test_virtual_document"
    VDOM.reset()
    
    assert.isNull(VDOM.virtualDocument)
  })
})

describe("shouldRenderElementVNode()", () => {
  it("returns true when element vnode doesn't have 'if' attribute", () => {
    const node = Type.elementNode("div")
    const bindings = Type.map()
    const result = VDOM.shouldRenderElementVNode(node, bindings)

    assert.isTrue(result)
  })

  it("returns true when element vnode has 'if' attribute which evaluates to a truthy value", () => {
    const attrs = {
      if: {
        modifiers: [],
        value: [Type.expressionNode(() => {
          return Type.tuple([Type.integer(123)])
        })]
      }
    }

    const node = Type.elementNode("div", attrs)
    const bindings = Type.map()
    const result = VDOM.shouldRenderElementVNode(node, bindings)

    assert.isTrue(result)
  })

  it("returns false when element vnode has 'if' attribute which evaluates to a falsy value", () => {
    const attrs = {
      if: {
        modifiers: [],
        value: [Type.expressionNode(() => {
          return Type.tuple([Type.nil()])
        })]
      }
    }

    const node = Type.elementNode("div", attrs)
    const bindings = Type.map()
    const result = VDOM.shouldRenderElementVNode(node, bindings)

    assert.isFalse(result)
  })
})
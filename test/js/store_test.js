"use strict";

import { assert, assertBoxedTrue, assertFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Store from "../../assets/js/hologram/store";
import Target from "../../assets/js/hologram/target";
import Type from "../../assets/js/hologram/type";
import Runtime from "../../assets/js/hologram/runtime";

import Map from "../../assets/js/hologram/elixir/map"

describe("buildContext()", () => {
  it("builds context", () => {
    const pageClassName = "test_page_class_name"
    const digest = "test_digest"
    const result = Store.buildContext(pageClassName, digest)

    const expected = {
      type: "map",
      data: {
        "~atom[__class__]": { type: "string", value: "test_page_class_name" },
        "~atom[__digest__]": { type: "string", value: "test_digest" },
        "~atom[__state__]": { type: "nil" }
      }
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("getComponentState()", () => {
  it("returns component state by component ID", () => {
    Store.setComponentState("test_id", "test_state")
    const result = Store.getComponentState("test_id")

    assert.equal(result, "test_state")
  })

  it("returns null if there is no state for the given component ID", () => {
    const result = Store.getComponentState("no_state")
    assert.isNull(result)
  })
})

describe("getLayoutState()", () => {
  Store.componentStateRegistry[Target.TYPE.layout] = "test_layout_state"
  const result = Store.getLayoutState()

  assert.equal(result, "test_layout_state")
})

describe("getPageState()", () => {
  Store.componentStateRegistry[Target.TYPE.page] = "test_page_state"
  const result = Store.getPageState()

  assert.equal(result, "test_page_state")
})

describe("hydrate()", () => {
  beforeEach(() => {
    const pageClassName = "test_page_class_name"
    const digest = "test_digest"

    let stateElems = {}
    stateElems[Type.atomKey("layout")] = Type.map()
    stateElems[Type.atomKey("page")] = Type.map()
    const state = Type.map(stateElems)

    Store.hydrate(pageClassName, digest, state)
  })

  it("hydrates layout state", () => {
    const layoutState = Store.getComponentState(Target.TYPE.layout)
    const isMap = Type.isMap(layoutState)
    const hasContextKey = Map.has_key$question(layoutState, Type.atom("__context__"))

    assert.isTrue(isMap)
    assertBoxedTrue(hasContextKey)
  })

  it("hydrates page state", () => {
    const pageState = Store.getComponentState(Target.TYPE.page)
    const isMap = Type.isMap(pageState)
    const hasContextKey = Map.has_key$question(pageState, Type.atom("__context__"))

    assert.isTrue(isMap)
    assertBoxedTrue(hasContextKey)
  })
})

describe("hydrateLayout()", () => {
  let layoutState;

  beforeEach(() => {
    const layoutStateElems = {}
    layoutStateElems[Type.atomKey("a")] = Type.integer(1)

    const stateElems = {}
    stateElems[Type.atomKey("layout")] = Type.map(layoutStateElems)
    const state = Type.map(stateElems)

    const context = Type.string("test_context")
    Store.hydrateLayout(state, context)

    layoutState = Store.getComponentState(Target.TYPE.layout)
  })

  it("hydrates layout state and saves it to the store", () => {
    const stateValue = Map.get(layoutState, Type.atom("a"))
    assert.deepStrictEqual(stateValue, Type.integer(1))
  })

  it("adds context data to the layout state", () => {
    const contextValue = Map.get(layoutState, Type.atom("__context__"))
    assert.deepStrictEqual(contextValue, Type.string("test_context"))
  })

  it("makes the layout state immutable", () => {
    assertFrozen(layoutState)
  })
})

describe("hydratePage()", () => {
  let pageState;

  beforeEach(() => {
    const pageStateElems = {}
    pageStateElems[Type.atomKey("a")] = Type.integer(1)

    const stateElems = {}
    stateElems[Type.atomKey("page")] = Type.map(pageStateElems)
    const state = Type.map(stateElems)

    const context = Type.string("test_context")
    Store.hydratePage(state, context)

    pageState = Store.getComponentState(Target.TYPE.page)
  })

  it("hydrates page state and saves it to the store", () => {
    const stateValue = Map.get(pageState, Type.atom("a"))
    assert.deepStrictEqual(stateValue, Type.integer(1))
  })

  it("adds context data to the page state", () => {
    const contextValue = Map.get(pageState, Type.atom("__context__"))
    assert.deepStrictEqual(contextValue, Type.string("test_context"))
  })

  it("makes the page state immutable", () => {
    assertFrozen(pageState)
  })
})

describe("resolveComponentState()", () => {
  const componentId = "test_id"

  it("returns state bindings of a stateful component", () => {
    const stateElems = {}
    stateElems[Type.atomKey("x")] = Type.integer(9)
    const state = Type.map(stateElems)

    Store.setComponentState(componentId, state)

    const props = Type.map()
    const result = Store.resolveComponentState(componentId, props)

    assert.deepStrictEqual(result, state)
  })

  it("inits the state of a stateful component if it hasn't been initiated yet", () => {
    const TestComponentClass = class {
      static init(props) {
        const stateElems = {}
        stateElems[Type.atomKey("state_key_1")] = Type.string("state_value_1")
        stateElems[Type.atomKey("state_key_2")] = Map.get(props, Type.atom("prop_key_1"))
        return Type.map(stateElems)
      }
    }

    Runtime.registerComponentClass(componentId, TestComponentClass)

    const propElems = {}
    propElems[Type.atomKey("prop_key_1")] = Type.string("prop_value_1")
    const props = Type.map(propElems)

    Store.resolveComponentState(componentId, props)
    const state = Store.getComponentState(componentId)

    const expectedStateElems = {}
    expectedStateElems[Type.atomKey("state_key_1")] = Type.string("state_value_1")
    expectedStateElems[Type.atomKey("state_key_2")] = Type.string("prop_value_1")
    const expectedState = Type.map(expectedStateElems)

    assert.deepStrictEqual(state, expectedState)
  })

  it("returns empty boxed map if the given componentId is null", () => {
    const result = Store.resolveComponentState(null)
    assert.deepStrictEqual(result, Type.map())
  })
})

describe("setComponentState()", () => {
  it("saves component state given component ID", () => {
    Store.setComponentState("component_2", 123)
    assert.equal(Store.componentStateRegistry.component_2, 123)
  })
})
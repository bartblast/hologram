"use strict";

import { assert, assertFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Store from "../../assets/js/hologram/store";
import Target from "../../assets/js/hologram/target";
import Type from "../../assets/js/hologram/type";
import Runtime from "../../assets/js/hologram/runtime";

import Map from "../../assets/js/hologram/elixir/map"

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
  let serializedState;

  beforeEach(() => {
    let layoutInitialStateElems = {}
    layoutInitialStateElems[Type.atomKey("x")] = Type.integer(987)
    const layoutInitialState = Type.map(layoutInitialStateElems)

    const TestLayoutClass = class {
      static init() {
        return layoutInitialState
      }
    }

    Runtime.registerLayoutClass(TestLayoutClass)

    let stateElems = {}
    stateElems[Type.atomKey("x")] = Type.integer(123)
    stateElems[Type.atomKey("context")] = Type.map({})
    const state = Type.map(stateElems)
    serializedState = JSON.stringify(state)

    Store.hydrate(serializedState)
  })

  it("hydrates layout state", () => {
    const state = Store.getLayoutState()
    const xValue = Map.get(state, Type.atom("x"))
    assert.deepStrictEqual(xValue, Type.integer(987))
  })

  it("hydrates page state", () => {
    const state = Store.getPageState()
    const xValue = Map.get(state, Type.atom("x"))
    assert.deepStrictEqual(xValue, Type.integer(123))
  })

  it("adds __state__ field to layout context", () => {
    const state = Store.getLayoutState()
    const context = Map.get(state, Type.atom("context"))
    const serializedStateValue = Map.get(context, Type.atom("__state__"))
    assert.deepStrictEqual(serializedStateValue, Type.string(serializedState))
  })

  it("adds __state__ field to page context", () => {
    const state = Store.getPageState()
    const context = Map.get(state, Type.atom("context"))
    const serializedStateValue = Map.get(context, Type.atom("__state__"))
    assert.deepStrictEqual(serializedStateValue, Type.string(serializedState))
  })
})

describe("hydrateLayout()", () => {
  let context, state;

  beforeEach(() => {
    let elems = {}
    elems[Type.atomKey("x")] = Type.integer(9)
    const testInitialState = Type.map(elems)

    const TestLayoutClass = class {
      static init() {
        return testInitialState
      }
    }

    Runtime.registerLayoutClass(TestLayoutClass)

    context = Type.string("test_context")
    Store.hydrateLayout(context)

    state = Store.getComponentState(Target.TYPE.layout)
  })

  it("initiates layout state and saves it to the store", () => {
    const xValue = Map.get(state, Type.atom("x"))
    assert.deepStrictEqual(xValue, Type.integer(9))
  })

  it("adds context data to the layout state", () => {
    const contextValue = Map.get(state, Type.atom("context"))
    assert.deepStrictEqual(contextValue, Type.string("test_context"))
  })

  it("makes the layout state immutable", () => {
    assertFrozen(state)
  })
})

describe("hydratePage()", () => {
  let context, state;

  beforeEach(() => {
    let elems = {}
    elems[Type.atomKey("x")] = Type.integer(9)
    const initialState = Type.map(elems)

    context = Type.string("test_context")

    Store.hydratePage(initialState, context)

    state = Store.getComponentState(Target.TYPE.page)
  })

  it("saves the page state to the store", () => {
    const xValue = Map.get(state, Type.atom("x"))
    assert.deepStrictEqual(xValue, Type.integer(9))
  })

  it("adds context data to the page state", () => {
    const contextValue = Map.get(state, Type.atom("context"))
    assert.deepStrictEqual(contextValue, Type.string("test_context"))
  })

  it("makes the page state immutable", () => {
    assertFrozen(state)
  })
})

describe("resolveComponentState()", () => {
  const TestComponentClass = class {
    static init() {
      return "init_result"
    }
  }

  const componentId = "test_id"

  it("returns state bindings of a stateful component", () => {
    const elems = {}
    elems[Type.atomKey("x")] = Type.integer(9)
    const state = Type.map(elems)

    Store.setComponentState(componentId, state)

    const result = Store.resolveComponentState(componentId)

    assert.deepStrictEqual(result, state)
  })

  it("inits the state of a stateful component if it hasn't been initiated yet", () => {
    Runtime.registerComponentClass(componentId, TestComponentClass)

    Store.resolveComponentState(componentId)
    const state = Store.getComponentState(componentId)

    assert.equal(state, "init_result")
  })

  it("returns empty boxed map if the given componentId is null", () => {
    const result = Store.resolveComponentState(null)
    assert.deepStrictEqual(result, Type.map({}))
  })
})

describe("setComponentState()", () => {
  it("saves component state given component ID", () => {
    Store.setComponentState("component_2", 123)
    assert.equal(Store.componentStateRegistry.component_2, 123)
  })
})
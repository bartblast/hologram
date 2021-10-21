"use strict";

import { assert, assertFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Operation from "../../assets/js/hologram/operation";
import Store from "../../assets/js/hologram/store";
import Type from "../../assets/js/hologram/type";
import Runtime from "../../assets/js/hologram/runtime";

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

describe("getPageState()", () => {
  Store.componentStateRegistry[Operation.TARGET.page] = "test_page_state"
  const result = Store.getPageState()

  assert.equal(result, "test_page_state")
})

describe("hydrate()", () => {
  let pageState, serializedState;

  beforeEach(() => {
    let stateData = {}
    stateData[Type.atomKey("x")] = Type.integer(123)
    stateData[Type.atomKey("context")] = Type.map({}, false)
    const state = Type.map(stateData, false)
    serializedState = JSON.stringify(state)

    Store.hydrate(serializedState)
    pageState = Store.getComponentState(Operation.TARGET.page)
  })

  it("saves correct page state to the store", () => {
    const expectedContextData = {}
    expectedContextData[Type.atomKey("__state__")] = Type.string(serializedState)

    const expectedPageStateData = {}
    expectedPageStateData[Type.atomKey("x")] = Type.integer(123)
    expectedPageStateData[Type.atomKey("context")] = Type.map(expectedContextData)
    const expectedPageState = Type.map(expectedPageStateData)

    assert.deepStrictEqual(pageState, expectedPageState)
  })

  it("saves frozen page state to the store", () => {
    assertFrozen(pageState)
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
"use strict";

import { assert, assertFrozen } from "./support/commons";
import Operation from "../../assets/js/hologram/operation";
import Store from "../../assets/js/hologram/store";
import Type from "../../assets/js/hologram/type";

const TestClass1 = class{}
const TestClass2 = class{}
const TestClass3 = class{}

Store.componentStateRegistry = {
  component_1: TestClass1,
  component_2: TestClass2,
  component_3: TestClass3
}

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

describe("getComponentState()", () => {
  it("returns component state given component ID", () => {
    const result = Store.getComponentState("component_2")
    assert.equal(result, TestClass2)
  })
})

describe("setComponentState()", () => {
  it("saves component state given component ID", () => {
    Store.setComponentState("component_2", 123)
    assert.equal(Store.componentStateRegistry.component_2, 123)
  })
})
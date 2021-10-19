"use strict";

import { assert, assertFrozen } from "./support/commons";
import Operation from "../../assets/js/hologram/operation";
import Runtime from "../../assets/js/hologram/runtime";
import Store from "../../assets/js/hologram/store";
import Type from "../../assets/js/hologram/type";

describe("determineLayoutClass()", () => {
  it("returns layout class given page class", () => {
    const TestLayoutClass = class {}
    globalThis.TestLayoutClass = TestLayoutClass


    const TestPageClass = class {
      static layout() {
        return Type.module("TestLayoutClass")
      }
    }

    const result = Runtime.determineLayoutClass(TestPageClass)

    assert.equal(result, TestLayoutClass)
  })
})

describe("getClassByClassName()", () => {
  it("returns class object given a class name", () => {
    const TestClass_Abc_Xyz = class {}
    globalThis.TestClass_Abc_Xyz = TestClass_Abc_Xyz
    
    const result = Runtime.getClassByClassName("TestClass_Abc_Xyz")

    assert.equal(result, TestClass_Abc_Xyz)
  })
})

describe("getComponentClass()", () => {
  it("returns component class given component ID", () => {
    const TestClass1 = class{}
    const TestClass2 = class{}
    const TestClass3 = class{}

    Runtime.componentClassRegistry = {
      component_1: TestClass1,
      component_2: TestClass2,
      component_3: TestClass3
    }

    const result = Runtime.getComponentClass("component_2")
    
    assert.equal(result, TestClass2)
  })
})

describe("getLayoutTemplate()", () => {
  it("returns the template of the current page's layout", () => {
    Runtime.layoutClass = class {
      static template() {
        return "test_template"
      }
    }

    const result = Runtime.getLayoutTemplate()

    assert.equal(result, "test_template")
  })
})

describe("getPageTemplate()", () => {
  it("returns the template of the current page", () => {
    Runtime.pageClass = class {
      static template() {
        return "test_template"
      }
    }

    const result = Runtime.getPageTemplate()

    assert.equal(result, "test_template")
  })
})

describe("setPageState()", () => {
  let pageState, serializedState;

  beforeEach(() => {
    let stateData = {}
    stateData[Type.atomKey("x")] = Type.integer(123)
    stateData[Type.atomKey("context")] = Type.map({}, false)
    const state = Type.map(stateData, false)
    serializedState = JSON.stringify(state)

    Runtime.setPageState(serializedState)
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
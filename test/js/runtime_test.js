"use strict";

import { assert, mockWindow } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";

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

describe("getInstance()", () => {
  globalThis.window = mockWindow()
  
  it("creates a new Runtime object if it doesn't exist yet", () => {
    const runtime = Runtime.getInstance()

    assert.isTrue(runtime instanceof Runtime)
    assert.equal(globalThis.__hologramRuntime__, runtime)
  })

  it("doesn't create a new Runtime object if it already exists", () => {    
    const runtime1 = Runtime.getInstance()
    const runtime2 = Runtime.getInstance()

    assert.equal(runtime2, runtime1)
  })
})
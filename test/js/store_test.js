"use strict";

import { assert } from "./support/commons";
import Store from "../../assets/js/hologram/store";

describe("getComponentState()", () => {
  it("returns component state given component ID", () => {
    const TestClass1 = class{}
    const TestClass2 = class{}
    const TestClass3 = class{}

    Store.componentStateRegistry = {
      component_1: TestClass1,
      component_2: TestClass2,
      component_3: TestClass3
    }

    const result = Store.getComponentState("component_2")
    
    assert.equal(result, TestClass2)
  })
})
"use strict";

import { assert } from "./support/commons";
import Store from "../../assets/js/hologram/store";

const TestClass1 = class{}
const TestClass2 = class{}
const TestClass3 = class{}

Store.componentStateRegistry = {
  component_1: TestClass1,
  component_2: TestClass2,
  component_3: TestClass3
}

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
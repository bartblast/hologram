"use strict";

import { assert, assertNotFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Runtime from "../../assets/js/hologram/runtime";
import Target from "../../assets/js/hologram/target";
import Type from "../../assets/js/hologram/type";

const layoutTarget = Target.TYPE.layout
const pageTarget = Target.TYPE.page

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

describe("getComponentClass()", () => {
  it("returns component class by the given component ID", () => {
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

  it("returns null if the given component ID is not registered", () => {
    const result = Runtime.getComponentClass("not_registered")
    assert.isNull(result)
  })
})

describe("getLayoutClass()", () => {
  it("returns the class of the current layout", () => {
    const TestLayoutClass = class {}
    Runtime.componentClassRegistry[layoutTarget] = TestLayoutClass
    const result = Runtime.getLayoutClass()

    assert.equal(result, TestLayoutClass)
  })
})

describe("getLayoutTemplate()", () => {
  it("returns the template of the current page's layout", () => {
    const TestLayoutClass = class {
      static template() {
        return "test_template"
      }
    }
    Runtime.registerLayoutClass(TestLayoutClass)

    const result = Runtime.getLayoutTemplate()

    assert.equal(result, "test_template")
  })
})

describe("getPageClass()", () => {
  it("returns the class of the current page", () => {
    const TestPageClass = class {}
    Runtime.componentClassRegistry[pageTarget] = TestPageClass
    const result = Runtime.getPageClass()

    assert.equal(result, TestPageClass)
  })
})

describe("getPageTemplate()", () => {
  it("returns the template of the current page", () => {
    const TestPageClass = class {
      static template() {
        return "test_template"
      }
    }
    Runtime.registerPageClass(TestPageClass)

    const result = Runtime.getPageTemplate()

    assert.equal(result, "test_template")
  })
})

describe("registerComponentClass()", () => {
  it("registers the class of the given component", () => {
    const TestComponentClass = class {}
    Runtime.registerComponentClass("testComponentId", TestComponentClass)

    assert.equal(Runtime.componentClassRegistry["testComponentId"], TestComponentClass)
  })
})

describe("registerLayoutClass()", () => {
  it("registers the given class as layout class", () => {
    const TestLayoutClass = class {}
    Runtime.registerLayoutClass(TestLayoutClass)

    assert.equal(Runtime.componentClassRegistry[layoutTarget], TestLayoutClass)
  })
})

describe("registerPageClass()", () => {
  it("registers the given class as page class", () => {
    const TestPageClass = class {}
    Runtime.registerPageClass(TestPageClass)

    assert.equal(Runtime.componentClassRegistry[pageTarget], TestPageClass)
  })
})

describe("resolveComponentClass()", () => {
  const TestComponentClass = class TestComponentClass {}
  const node = Type.componentNode(TestComponentClass, {}, [])

  it("returns the already registered class of a stateful component", () => {
    Runtime.registerComponentClass("test_id", TestComponentClass)
    const result = Runtime.resolveComponentClass(node, "test_id")

    assert.equal(result, TestComponentClass)
  })

  it("returns the not registered yet class of a stateful component and registers it", () => {
    assert.isNull(Runtime.getComponentClass("test_id"))

    const result = Runtime.resolveComponentClass(node, "test_id")
    assert.equal(result.name, "TestComponentClass")

    const registeredClassName = Runtime.componentClassRegistry["test_id"].name
    assert.equal(registeredClassName, "TestComponentClass")
  })

  it("returns the class of a stateless component", () => {
    const result = Runtime.resolveComponentClass(node, null)
    assert.equal(result.name, "TestComponentClass")
  })
})
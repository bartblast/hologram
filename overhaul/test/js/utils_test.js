"use strict";

import { assert, assertFrozen, assertNotFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Utils from "../../assets/js/hologram/utils";

describe("exec()", () => {
  it("executes given JS code", () => {
    const TestClass = class {
      static testField = null
    }

    globalThis.TestClass = TestClass

    Utils.exec("TestClass.testField = 'testValue'")

    assert.equal(TestClass.testField, "testValue")
  })
})

describe("freeze()", () => {
  it("freezes object and all of its properties recursively (deep freeze)", () => {
    let obj = {
      a: {
        b: {
          c: {
            d: 1
          }
        }
      }
    }

    Utils.freeze(obj)

    assertFrozen(obj.a)
    assertFrozen(obj.a.b)
    assertFrozen(obj.a.b.c)
  })
})
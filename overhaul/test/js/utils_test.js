"use strict";

import { assert, assertFrozen, assertNotFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Utils from "../../assets/js/hologram/utils";

describe("clone()", () => {
  let obj, result;

  beforeEach(() => {
    obj = {a: 1, b: {c: 3, d: 4}}
    result = Utils.clone(obj)
  })

  it("clones object recursively (deep clone)", () => {
    assert.deepStrictEqual(result, obj) 
    assert.notEqual(result, obj)
  })

  it("returns unfrozen object", () => {
    assertNotFrozen(result)
  })
})

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

describe("eval()", () => {
  let result;

  beforeEach(() => {
    result = Utils.eval("{value: 2 + 2}")
  })

  it("evaluates code", () => {
    assert.deepStrictEqual(result, {value: 4})
  })

  it("returns frozen object by default", () => {
    assertFrozen(result)
  })

  it("returns not frozen object if second arg is false", () => {
    result = Utils.eval("{value: 2 + 2}", false)
    assertNotFrozen(result)
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
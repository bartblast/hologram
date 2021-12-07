"use strict";

import {
  assert,
  assertBoxedNil,
  assertFrozen,
  cleanup,
} from "../../../support/commons";
beforeEach(() => cleanup());

import JS from "../../../../../assets/js/hologram/elixir/hologram/runtime/js"

describe("exec()", () => {
  it("executes given JS code", () => {
    const TestClass = class {
      static testField = null
    }

    globalThis.TestClass = TestClass

    JS.exec("TestClass.testField = 'testValue'")

    assert.equal(TestClass.testField, "testValue")
  })

  it("returns boxed, freezed nil", () => {
    const result = JS.exec("1 + 2")

    assertBoxedNil(result)
    assertFrozen(result)
  })
})
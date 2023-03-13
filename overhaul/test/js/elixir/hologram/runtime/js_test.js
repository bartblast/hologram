"use strict";

import {
  assert,
  cleanup,
} from "../../../support/commons";
beforeEach(() => cleanup());

import JS from "../../../../../assets/js/hologram/elixir/hologram/runtime/js"
import Type from "../../../../../assets/js/hologram/type"

describe("exec()", () => {
  it("executes JS code evaluated from the given boxed arg", () => {
    const TestClass = class {
      static testField = null
    }

    globalThis.TestClass = TestClass

    const code = Type.binary([
      Type.string("TestClass.testField"),
      Type.string(" = "),
      Type.string("'testValue'")
    ])

    JS.exec(code)

    assert.equal(TestClass.testField, "testValue")
  })
})
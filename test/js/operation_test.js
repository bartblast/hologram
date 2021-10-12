"use strict";

import { assert } from "./support/commons";
import Enums from "../../assets/js/hologram/enums"
import Operation from "../../assets/js/hologram/operation"
import Type from "../../assets/js/hologram/type"

describe("buildMethod()", () => {
  it("returns command enum value if the modifiers in operation spec include 'command'", () => {
    const operationSpec = {
      modifiers: ["command"]
    }

    const result = Operation.buildMethod(operationSpec)
    const expected = Enums.OPERATION_METHOD.command

    assert.equal(result, expected)
  })

  it("returns action enum value if the modifiers in operation spec don't include 'command'", () => {
    const operationSpec = {
      modifiers: ["command8888"]
    }

    const result = Operation.buildMethod(operationSpec)
    const expected = Enums.OPERATION_METHOD.action

    assert.equal(result, expected)
  })
})

describe("getSpecType()", () => {
  it("returns expression enum value if the operation spec value is an expression node", () => {
    const operationSpec = {
      value: [Type.expressionNode(null)]
    }

    const result = Operation.getSpecType(operationSpec)
    const expected = Enums.OPERATION_SPEC_TYPE.expression

    assert.equal(result, expected)
  })

  it("returns text enum value if the operation spec value is a text node", () => {
    const operationSpec = {
      value: [Type.textNode("test")]
    }

    const result = Operation.getSpecType(operationSpec)
    const expected = Enums.OPERATION_SPEC_TYPE.text

    assert.equal(result, expected)
  })
})
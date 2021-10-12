"use strict";

import { assert } from "./support/commons";
import Enums from "../../assets/js/hologram/enums"
import Operation from "../../assets/js/hologram/operation"

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
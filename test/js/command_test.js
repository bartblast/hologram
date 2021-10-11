"use strict";

import { assert, mockWindow } from "./support/commons";
import Command from "../../assets/js/hologram/command"
import Runtime from "../../assets/js/hologram/runtime"
import Type from "../../assets/js/hologram/type"

describe("Operation class extension", () => {
  it("extends Operation class", () => {
    const operationSpec = {
      value: [Type.textNode("test")]
    }

    const TestTargetModule = class {}
    const context = {targetModule: TestTargetModule}
    const eventData = "test_event_data"

    const window = mockWindow()
    const runtime = new Runtime(window)

    const result = Command.build(operationSpec, eventData, context, runtime)

    assert.isTrue(result instanceof Command)
  })
})
"use strict";

import { assert } from "./support/commons";
import Operation from "../../assets/js/hologram/operation"
import Type from "../../assets/js/hologram/type"

const TestTargetModule = class {}

describe("buildFromTextNodeSpec()", () => {
  it("builds operation from a text node spec", () => {
    const context = {targetModule: TestTargetModule}
    const textNode = Type.textNode("test")

    const result = Operation.buildFromTextNodeSpec(textNode, context)
    const expected = new Operation(TestTargetModule, null, Type.atom("test"), Type.map({}))

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })
})
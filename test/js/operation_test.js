"use strict";

import { assert, assertFrozen } from "./support/commons";
import Operation from "../../assets/js/hologram/operation"
import Type from "../../assets/js/hologram/type"

const bindings = Type.map({})
const source = "test_source"

const textOperationSpec = {
  modifiers: [],
  value: [Type.textNode("test_action")]
}

describe("build()", () => {
  it("returns a frozen Operation object", () => {
    const result = Operation.build(textOperationSpec, source, bindings, Type.map({}))

    assert.isTrue(result instanceof Operation)
    assertFrozen(result)
  })
})

describe("buildMethod()", () => {
  it("returns command enum value if the modifiers in operation spec include 'command'", () => {
    const operationSpec = {
      modifiers: ["command"]
    }

    const result = Operation.buildMethod(operationSpec)
    const expected = Operation.METHOD.command

    assert.equal(result, expected)
  })

  it("returns action enum value if the modifiers in operation spec don't include 'command'", () => {
    const operationSpec = {
      modifiers: ["command8888"]
    }

    const result = Operation.buildMethod(operationSpec)
    const expected = Operation.METHOD.action

    assert.equal(result, expected)
  })
})

describe("buildName()", () => {
  const expected = Type.atom("test_action")

  it("returns the first spec elem if the operation spec has only one elem", () => {
    const specElems = [Type.atom("test_action")]
    const result = Operation.buildName(specElems)

    assert.deepStrictEqual(result, expected)
  })

  it("returns the first spec elem if the second operation spec elem is not of boxed atom type", () => {
    const specElems = [Type.atom("test_action"), Type.integer(1)]
    const result = Operation.buildName(specElems)

    assert.deepStrictEqual(result, expected)
  })

  it("returns the second spec elem if the operation spec has at least two elems and the second one is of boxed atom type", () => {
    const specElems = [Type.atom("layout"), Type.atom("test_action")]
    const result = Operation.buildName(specElems)

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const specElems = [Type.atom("test_action")]
    const result = Operation.buildName(specElems)

    assertFrozen(result)
  })
})

describe("buildParams()", () => {
  const params = Type.list([
    Type.tuple([Type.atom("a"), Type.integer(1)]),
    Type.tuple([Type.atom("b"), Type.integer(2)]),
  ])

  const eventDataElems = {}
  eventDataElems[Type.atomKey("x")] = Type.integer(1)
  const eventData = Type.map(eventDataElems)

  const expected = Type.list([
    Type.tuple([Type.atom("event"), eventData]),
    Type.tuple([Type.atom("a"), Type.integer(1)]),
    Type.tuple([Type.atom("b"), Type.integer(2)])
  ])

  it("returns the third spec elem if the operation spec has three elems", () => {
    const specElems = [Type.atom("test_target"), Type.atom("test_action"), params]
    const result = Operation.buildParams(specElems, eventData)

    assert.deepStrictEqual(result, expected)
  })

  it("returns the second spec elem if the operation spec has two elems and the second one is of boxed list type", () => {
    const specElems = [Type.atom("test_action"), params]
    const result = Operation.buildParams(specElems, eventData)

    assert.deepStrictEqual(result, expected)
  })

  it("returns a boxed keyword list with 'event' key only if the operation spec doesn't contain params", () => {
    const specElems = [Type.atom("test_target"), Type.atom("test_action")]

    const result = Operation.buildParams(specElems, eventData)
    
    const expected = Type.list([
      Type.tuple([Type.atom("event"), eventData])
    ])

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const specElems = [Type.atom("test_action")]
    const result = Operation.buildParams(specElems, eventData)

    assertFrozen(result)
  })
})

describe("buildTarget()", () => {
  it("returns the source arg if the operation spec doesn't contain target value", () => {
    const specElems = [Type.textNode("test_action")]
    const result = Operation.buildTarget(specElems, source)

    assert.equal(result, source)
  })

  it("returns layout enum value if the operation spec target value is equal to 'layout' boxed atom", () => {
    const specElems = [Type.atom("layout"), Type.atom("test_action")]

    const result = Operation.buildTarget(specElems, source)
    const expected = Operation.TARGET.layout

    assert.equal(result, expected)
  })

  it("returns page enum value if the operation spec target value is equal to 'page' boxed atom", () => {
    const specElems = [Type.atom("page"), Type.atom("test_action")]

    const result = Operation.buildTarget(specElems, source)
    const expected = Operation.TARGET.page

    assert.equal(result, expected)
  })

  it("returns unboxed target value if the operation spec contains a boxed target value", () => {
    const specElems = [Type.atom("test_target"), Type.atom("test_action")]

    const result = Operation.buildTarget(specElems, source)
    const expected = "test_target"

    assert.equal(result, expected)
  })
})

describe("getSpecElems()", () => {
  it("returns operation spec elems when the operation spec is of text type", () => {
    const result = Operation.getSpecElems(textOperationSpec, bindings)
    const expected = [Type.atom("test_action")]

    assert.deepStrictEqual(result, expected)
  })

  it("returns operation spec elems when the operation spec is of expression type", () => {
    const callback = (_$bindings) => { return Type.tuple([Type.atom("layout"), Type.atom("test_action")]) }

    const operationSpec = {
      value: [Type.expressionNode(callback)]
    }

    const result = Operation.getSpecElems(operationSpec, bindings)
    const expected = [Type.atom("layout"), Type.atom("test_action")]

    assert.deepStrictEqual(result, expected)
  })

  it("returns frozen object", () => {
    const operationSpec = {
      value: [Type.textNode("test_action")]
    }

    const result = Operation.getSpecElems(operationSpec, bindings)

    assertFrozen(result)
  })
})

describe("getSpecType()", () => {
  it("returns expression enum value if the operation spec value is an expression node", () => {
    const operationSpec = {
      value: [Type.expressionNode(null)]
    }

    const result = Operation.getSpecType(operationSpec)
    const expected = Operation.SPEC_TYPE.expression

    assert.equal(result, expected)
  })

  it("returns text enum value if the operation spec value is a text node", () => {
    const result = Operation.getSpecType(textOperationSpec)
    const expected = Operation.SPEC_TYPE.text

    assert.equal(result, expected)
  })
})

describe("getTargetValue()", () => {
  it("returns null if the operation spec has only one elem", () => {
    const specElems = [Type.atom("layout")]
    const result = Operation.getTargetValue(specElems)

    assert.isNull(result)
  })

  it("returns null if the second operation spec elem is not a boxed atom", () => {
    const specElems = [Type.atom("layout"), Type.integer(1)]
    const result = Operation.getTargetValue(specElems)

    assert.isNull(result)
  })

  it("returns unboxed target value if the operation spec contains a boxed atom target value", () => {
    const specElems = [Type.atom("test_target"), Type.atom("test_action")]
    const result = Operation.getTargetValue(specElems)

    assert.equal(result, "test_target")
  })
})
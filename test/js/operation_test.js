"use strict";

import { assert, fixtureOperationParamsKeyword, fixtureOperationParamsMap, fixtureOperationSpecExpressionNode } from "./support/commons";
import Operation from "../../assets/js/hologram/operation"
import Type from "../../assets/js/hologram/type"

const TestLayoutModule = class {}
const TestPageModule = class {}
const TestTargetModule = class {}

const TestComponentModule1 = class {}
const TestComponentModule2 = class {}

describe("buildFromExpressionNodeSpec()", () => {
  let context;

  beforeEach(() => {
    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetModule: TestTargetModule,
      targetId: "test_target_id"
    }
  })

  it("builds operation from an expression node spec with target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("page"),
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = Operation.buildFromExpressionNodeSpec(expressionNode, context)

    const expected = {
      targetModule: TestPageModule,
      targetId: null,
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds operation from an expression node spec without target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = Operation.buildFromExpressionNodeSpec(expressionNode, context)

    const expected = {
      targetModule: TestTargetModule,
      targetId: "test_target_id",
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildFromExpressionNodeSpecWithTarget()", () => {
  let componentRegistry, context, name, paramsKeyword, paramsMap;

  beforeEach(() => {
    name = Type.atom("test")
    paramsKeyword = fixtureOperationParamsKeyword()
    paramsMap = fixtureOperationParamsMap()

    context = {
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule
    }

    componentRegistry = {
      test_component_1: TestComponentModule1,
      test_component_2: TestComponentModule2
    }
  })

  it("builds layout target operation if the first spec elem is equal to :layout boxed atom", () => {
    const target = Type.atom("layout")
    const specElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(specElems, context, componentRegistry)
    const expected = new Operation(TestLayoutModule, null, name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })

  it("builds page target operation if the first spec elem is equal to :page boxed atom", () => {
    const target = Type.atom("page")
    const specElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(specElems, context, componentRegistry)
    const expected = new Operation(TestPageModule, null, name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })

  it("builds component target operation if the first spec elem is different than :page or :layout boxed atom", () => {
    const target = Type.atom("test_component_2")
    const specElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(specElems, context, componentRegistry)
    const expected = new Operation(TestComponentModule2, "test_component_2", name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })
})

describe("buildFromExpressionNodeSpecWithoutTarget()", () => {
  it("builds operation from an expression node spec without target specified", () => {
    const name = Type.atom("test")
    const paramsKeyword = fixtureOperationParamsKeyword()

    const specElems = [
      name,
      paramsKeyword
    ]

    const context = {targetModule: TestTargetModule, targetId: "test_id"}

    const result = Operation.buildFromExpressionNodeSpecWithoutTarget(specElems, context)
    const expected = new Operation(TestTargetModule, "test_id", name, fixtureOperationParamsMap())

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })
})

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

describe("hasSpecTarget()", () => {
  it("returns true if the first 2 spec elems are bounded atoms", () => {
    const specElems = [Type.atom("a"), Type.atom("b")]
    const result = Operation.hasSpecTarget(specElems)

    assert.isTrue(result)
  })

  it("returns false if there is only 1 spec elem", () => {
    const specElems = [Type.atom("a")]
    const result = Operation.hasSpecTarget(specElems)

    assert.isFalse(result)
  })

  it("returns false if the first spec elem is not a bounded atom", () => {
    const specElems = [Type.integer(1), Type.atom("b")]
    const result = Operation.hasSpecTarget(specElems)

    assert.isFalse(result)
  })

  it("returns false if the second spec elem is not a bounded atom", () => {
    const specElems = [Type.atom("a"), Type.integer(2)]
    const result = Operation.hasSpecTarget(specElems)

    assert.isFalse(result)
  })
})
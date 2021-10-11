"use strict";

import { assert, fixtureOperationParamsKeyword, fixtureOperationParamsMap, fixtureOperationSpecExpressionNode, mockWindow } from "./support/commons";
import Operation from "../../assets/js/hologram/operation"
import Type from "../../assets/js/hologram/type"
import Runtime from "../../assets/js/hologram/runtime";

const TestLayoutModule = class {}
const TestPageModule = class {}
const TestTargetModule = class {}

const TestComponentModule1 = class {}
const TestComponentModule2 = class {}

describe("build()", () => {
  let context, expected, runtime;

  beforeEach(() => {
    const window = mockWindow()
    runtime = new Runtime(window)

    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetModule: TestTargetModule,
      targetId: "test_target_id"
    }

    expected = Type.atom("test_action")
  })

  it("builds operation from spec which contains expression node", () => {
    const operationSpecTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const operationSpec = {
      value: [fixtureOperationSpecExpressionNode(operationSpecTuple)]
    }

    const result = Operation.build(operationSpec, context, runtime)
    
    assert.deepStrictEqual(result.name, expected)
  })

  it("builds operation from spec which contains text node", () => {
    const operationSpec = {
      value: [Type.textNode("test_action")]
    }

    const result = Operation.build(operationSpec, context, runtime)
    
    assert.deepStrictEqual(result.name, expected)
  })
})

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
    const operationSpecTuple = Type.tuple([
      Type.atom("page"),
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(operationSpecTuple)

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
    const operationSpecTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(operationSpecTuple)

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
    const operationSpecElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(operationSpecElems, context, componentRegistry)
    const expected = new Operation(TestLayoutModule, null, name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })

  it("builds page target operation if the first spec elem is equal to :page boxed atom", () => {
    const target = Type.atom("page")
    const operationSpecElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(operationSpecElems, context, componentRegistry)
    const expected = new Operation(TestPageModule, null, name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })

  it("builds component target operation if the first spec elem is different than :page or :layout boxed atom", () => {
    const target = Type.atom("test_component_2")
    const operationSpecElems = [target, name, paramsKeyword]

    const result = Operation.buildFromExpressionNodeSpecWithTarget(operationSpecElems, context, componentRegistry)
    const expected = new Operation(TestComponentModule2, "test_component_2", name, paramsMap)

    assert.isTrue(result instanceof Operation)
    assert.deepStrictEqual(result, expected)
  })
})

describe("buildFromExpressionNodeSpecWithoutTarget()", () => {
  it("builds operation from an expression node spec without target specified", () => {
    const name = Type.atom("test")
    const paramsKeyword = fixtureOperationParamsKeyword()
    const operationSpecElems = [name, paramsKeyword]
    const context = {targetModule: TestTargetModule, targetId: "test_id"}

    const result = Operation.buildFromExpressionNodeSpecWithoutTarget(operationSpecElems, context)
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

describe("hasTarget()", () => {
  it("returns true if the first 2 spec elems are bounded atoms", () => {
    const operationSpecElems = [Type.atom("a"), Type.atom("b")]
    const result = Operation.hasTarget(operationSpecElems)

    assert.isTrue(result)
  })

  it("returns false if there is only 1 spec elem", () => {
    const operationSpecElems = [Type.atom("a")]
    const result = Operation.hasTarget(operationSpecElems)

    assert.isFalse(result)
  })

  it("returns false if the first spec elem is not a bounded atom", () => {
    const operationSpecElems = [Type.integer(1), Type.atom("b")]
    const result = Operation.hasTarget(operationSpecElems)

    assert.isFalse(result)
  })

  it("returns false if the second spec elem is not a bounded atom", () => {
    const operationSpecElems = [Type.atom("a"), Type.integer(2)]
    const result = Operation.hasTarget(operationSpecElems)

    assert.isFalse(result)
  })
})
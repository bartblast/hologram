"use strict";

import { assert, fixtureOperationParamsKeyword, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Action from "../../assets/js/hologram/action"
import Runtime from "../../assets/js/hologram/runtime"
import Target from "../../assets/js/hologram/target"
import Type from "../../assets/js/hologram/type"

const state = Type.map()
const targetId = Type.atom("test_target_id")
const commandName = Type.atom("test_command")
const params = Type.list()

describe("getCommandNameFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map()
    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.isNull(result)
  })

  it("fetches the command name from an action result that is a 4-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName,
      params
    ])

    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.deepStrictEqual(result, commandName)
  })

  it("fetches the command name from an action result that is a 3-element boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName
    ])

    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.deepStrictEqual(result, commandName)
  })

  it("fetches the command name from an action result that is a 3-element boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      state,
      commandName,
      params
    ])

    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.deepStrictEqual(result, commandName)
  })

  it("fetches the command name from an action result that is a 2-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      commandName
    ])

    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.deepStrictEqual(result, commandName)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain command name", () => {
    const actionResult = Type.tuple([
      Type.map(),
    ])

    const result = Action.getCommandNameFromActionResult(actionResult)

    assert.isNull(result)
  })
})

describe("getParamsFromActionResult()", () => {
  const paramsKeyword = fixtureOperationParamsKeyword()

  it("returns empty keyword list if the action result is a boxed map", () => {
    const actionResult = Type.map()
    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, Type.list())
  })

  it("fetches the command params from an action result that is a 4-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName,
      paramsKeyword
    ])

    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, paramsKeyword)
  })

  it("fetches the command params from an action result that is a 3-element boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      state,
      commandName,
      paramsKeyword
    ])

    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, paramsKeyword)
  })

  it("returns empty keyword list if the  action result is a 3-element boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName
    ])

    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, Type.list())
  })

  it("returns empty keyword list if the action result is a 2-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      commandName
    ])

    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, Type.list())
  })

  it("returns empty keyword list if the action result is a 1-element boxed tuple", () => {
    const actionResult = Type.tuple([state])
    const result = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(result, Type.list())
  })
})

describe("getStateFromActionResult()", () => {
  it("fetches the state from an action result that is a boxed map", () => {
    const actionResult = Type.map()
    const result = Action.getStateFromActionResult(actionResult)

    assert.equal(result, actionResult)
  })

  it("fetches the state from an action result that is a boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      commandName
    ])

    const result = Action.getStateFromActionResult(actionResult)

    assert.deepStrictEqual(result, state)
  })
})

describe("getTargetIdFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map()
    const result = Action.getTargetIdFromActionResult(actionResult)

    assert.isNull(result)
  })

  it("fetches the target id from an action result that is a 4-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName,
      params
    ])

    const result = Action.getTargetIdFromActionResult(actionResult)

    assert.deepStrictEqual(result, targetId)
  })

  it("fetches the target id from an action result that is a 3-element boxed tuple that contains target id", () => {
    const actionResult = Type.tuple([
      state,
      targetId,
      commandName
    ])

    const result = Action.getTargetIdFromActionResult(actionResult)

    assert.deepStrictEqual(result, targetId)
  })

  it("returns null if the action result is a 2-element boxed tuple", () => {
    const actionResult = Type.tuple([
      state,
      commandName
    ])

    const result = Action.getTargetIdFromActionResult(actionResult)

    assert.isNull(result)
  })

  it("returns null if the action result is a 1-element boxed tuple", () => {
    const actionResult = Type.tuple([state])
    const result = Action.getTargetIdFromActionResult(actionResult)

    assert.isNull(result)
  })
})

describe("resolveCommandTarget()", () => {
  it("creates Target object when command target is present in action result", () => {
    const commandTargetId = Type.atom("test_command_target_id")

    const actionResult = Type.tuple([
      state,
      commandTargetId,
      commandName
    ])

    const TestComponentClass1 = class {}
    Runtime.registerComponentClass(targetId.value, TestComponentClass1)
    const actionTarget = new Target(targetId.value)

    const TestComponentClass2 = class {}
    Runtime.registerComponentClass(commandTargetId.value, TestComponentClass2)

    const result = Action.resolveCommandTarget(actionResult, actionTarget)
    
    assert.isTrue(result instanceof Target)
    assert.equal(result.id, commandTargetId.value)
  })

  it("creates Target object when command target is not present in action result", () => {
    const actionResult = Type.tuple([state])

    const TestComponentClass = class {}
    Runtime.registerComponentClass(targetId.value, TestComponentClass)
    const actionTarget = new Target(targetId.value)

    const result = Action.resolveCommandTarget(actionResult, actionTarget)
    
    assert.isTrue(result instanceof Target)
    assert.equal(result.id, targetId.value)
  })
})
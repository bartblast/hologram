"use strict";

import { assert, fixtureOperationParamsKeyword } from "./support/commons";
import Action from "../../assets/js/hologram/action"
import Type from "../../assets/js/hologram/type"

describe("getCommandNameFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const commandName = Action.getCommandNameFromActionResult(actionResult)

    assert.isNull(commandName)
  })

  it("fetches the command name from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command")
    ])

    const commandName = Action.getCommandNameFromActionResult(actionResult)
    const expected = Type.atom("test_command")

    assert.deepStrictEqual(commandName, expected)
  })

  it("fetches the command name from an action result that is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_command")
    ])

    const commandName = Action.getCommandNameFromActionResult(actionResult)
    const expected = Type.atom("test_command")

    assert.deepStrictEqual(commandName, expected)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain command name", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const commandName = Action.getCommandNameFromActionResult(actionResult)

    assert.isNull(commandName)
  })
})

describe("getParamsFromActionResult()", () => {
  const paramsKeyword = fixtureOperationParamsKeyword()

  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const commandParams = Action.getParamsFromActionResult(actionResult)

    assert.isNull(commandParams)
  })

  it("fetches the command params from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command"),
      paramsKeyword
    ])

    const commandParams = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(commandParams, paramsKeyword)
  })

  it("fetches the command params from an action result that is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_command"),
      paramsKeyword
    ])

    const commandParams = Action.getParamsFromActionResult(actionResult)

    assert.deepStrictEqual(commandParams, paramsKeyword)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain command params", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const commandParams = Action.getParamsFromActionResult(actionResult)

    assert.isNull(commandParams)
  })
})

describe("getStateFromActionResult()", () => {
  it("fetches the state from an action result that is a boxed map", () => {
    const actionResult = Type.map({})
    const state = Action.getStateFromActionResult(actionResult)

    assert.equal(state, actionResult)
  })

  it("fetches the state from an action result that is a boxed tuple", () => {
    const actionResult = Type.tuple([Type.map({}), Type.atom("test_command")])
    const state = Action.getStateFromActionResult(actionResult)

    assert.deepStrictEqual(state, Type.map({}))
  })
})

describe("getTargetFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const target = Action.getTargetFromActionResult(actionResult)

    assert.isNull(target)
  })

  it("fetches the target from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command")
    ])

    const target = Action.getTargetFromActionResult(actionResult)
    const expected = Type.atom("test_target")

    assert.deepStrictEqual(target, expected)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const target = Action.getTargetFromActionResult(actionResult)

    assert.isNull(target)
  })
})
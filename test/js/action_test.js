"use strict";

import { assert } from "./support/commons";
import Action from "../../assets/js/hologram/action"
import Type from "../../assets/js/hologram/type"

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
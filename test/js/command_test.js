"use strict";

import { assert, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Command from "../../assets/js/hologram/command"
import Operation from "../../assets/js/hologram/operation"
import Runtime from "../../assets/js/hologram/runtime"
import Target from "../../assets/js/hologram/target"
import Type from "../../assets/js/hologram/type"

describe("buildMessagePayload()", () => {
  it("builds command message payload", () => {
    const targetId = "test_target_id"
    const TestComponentClass = class {}
    Runtime.registerComponentClass(targetId, TestComponentClass)
    const target = new Target(targetId)

    const sourceId = "test_source_id"
    const commandName = Type.atom("test_command_name")
    const params = Type.list()

    const operation = new Operation(sourceId, target, commandName, params)
    const result = Command.buildMessagePayload(operation)

    const expected = {
      target_module: Type.module("TestComponentClass"),
      target_id: Type.atom(targetId),
      command: commandName,
      params: params,
    }

    assert.deepStrictEqual(result, expected)
  })
})
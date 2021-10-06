"use strict";

import { assert } from "./support/commons";
import Client from "../../assets/js/hologram/client";
import Type from "../../assets/js/hologram/type";

describe("buildMessagePayload()", () => {
  it("builds payload of a command message sent to backend", () => {
    const TestTargetModule = class {}
    const command = "test_command"

    let elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    const params = Type.map(elems)

    const expected = {
      target_module: {type: "module", className: "TestTargetModule"},
      command: {type: "atom", value: "test_command"},
      params: params
    }

    const result = Client.buildMessagePayload(TestTargetModule, command, params)

    assert.deepStrictEqual(result, expected);
  });
});
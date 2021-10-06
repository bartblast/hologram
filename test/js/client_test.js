"use strict";

import { assert } from "./support/commons";
import Client from "../../assets/js/hologram/client";

describe("buildMessagePayload()", () => {
  it("builds payload of a command message sent to backend", () => {
    const TestTargetModule = class {}
    const command = "test_command"
    const params = {a: 1, b: 2}

    const expected = {
      target_module: "TestTargetModule",
      command: command,
      params: params
    }

    const result = Client.buildMessagePayload(TestTargetModule, command, params)

    assert.deepStrictEqual(result, expected);
  });
});
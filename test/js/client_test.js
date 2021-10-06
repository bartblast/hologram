"use strict";

import { assert } from "./support/commons";
import Client from "../../assets/js/hologram/client";
import Type from "../../assets/js/hologram/type";

describe("buildCommandPayload()", () => {
  it("builds payload of a command message sent to backend", () => {
    const TestTargetModule = class {}
    const name = Type.atom("test_command")

    let elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = Type.integer(2)
    const params = Type.map(elems)

    const expected = {
      target_module: {type: "module", className: "TestTargetModule"},
      name: name,
      params: params
    }

    const result = Client.buildCommandPayload(TestTargetModule, name, params)

    assert.deepStrictEqual(result, expected);
  });
});
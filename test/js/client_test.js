import { assert } from "./support/commons";
import Client from "../../assets/js/hologram/client";

describe("buildMessagePayload()", () => {
  it("builds correct message payload", () => {
    const command = "test_command"
    const params = {a: 1, b: 2}

    const TestPageModule = class {}
    const TestScopeModule = class {}

    const context = {
      pageModule: TestPageModule,
      scopeModule: TestScopeModule
    }

    const expected = {
      command: 'test_command',
      context: {
        page_module: 'TestPageModule',
        scope_module: 'TestScopeModule' 
      },
      params: {a: 1, b: 2}
    }

    const result = Client.buildMessagePayload(command, params, context)

    assert.deepStrictEqual(result, expected);
  });
});
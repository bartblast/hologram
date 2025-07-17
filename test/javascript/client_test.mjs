"use strict";

import {
  assert,
  componentRegistryEntryFixture,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Client", () => {
  describe("buildCommandPayload()", () => {
    const module = Type.alias("MyComponent");

    const name = Type.atom("my_command");

    const params = Type.map([
      [Type.atom("param_1"), Type.integer(1)],
      [Type.atom("param2"), Type.integer(2)],
    ]);

    const target = Type.bitstring("my_target");

    const command = Type.commandStruct({name, params, target});

    beforeEach(() => {
      ComponentRegistry.clear();
    });

    it("builds command payload when target component is registered", () => {
      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(target, entry);

      const result = Client.buildCommandPayload(command);

      const expected = Type.map([
        [Type.atom("module"), module],
        [Type.atom("name"), name],
        [Type.atom("params"), params],
        [Type.atom("target"), target],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("throws error when target component is not registered", () => {
      // Don't register the component, so it will not be found

      assert.throws(
        () => Client.buildCommandPayload(command),
        HologramRuntimeError,
        'invalid command target, there is no component with CID: "my_target"',
      );
    });
  });
});

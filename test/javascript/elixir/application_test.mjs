"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ApplicationEnv from "../../../assets/js/erts/application_env.mjs";
import Elixir_Application from "../../../assets/js/elixir/application.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/application_test.exs
// Always update both together.

describe("Elixir_Application", () => {
  beforeEach(() => {
    ApplicationEnv.clear();
  });

  describe("get_env/3", () => {
    const get_env = Elixir_Application["get_env/3"];

    it("returns value when app env is set", () => {
      ApplicationEnv.put(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.integer(42),
      );

      const result = get_env(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.nil(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns default when app is not set", () => {
      const result = get_env(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.atom("default"),
      );

      assert.deepStrictEqual(result, Type.atom("default"));
    });

    it("returns default when key is not set", () => {
      ApplicationEnv.put(
        Type.atom("my_app"),
        Type.atom("other_key"),
        Type.integer(1),
      );

      const result = get_env(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.atom("default"),
      );

      assert.deepStrictEqual(result, Type.atom("default"));
    });
  });
});

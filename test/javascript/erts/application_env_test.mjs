"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ApplicationEnv from "../../../assets/js/erts/application_env.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ApplicationEnv", () => {
  beforeEach(() => {
    ApplicationEnv.clear();
  });

  it("clear()", () => {
    ApplicationEnv.put(
      Type.atom("my_app"),
      Type.atom("my_key"),
      Type.integer(1),
    );

    assert.equal(ApplicationEnv.data.size, 1);

    ApplicationEnv.clear();

    assert.equal(ApplicationEnv.data.size, 0);
  });

  describe("get()", () => {
    it("returns value when app and key exist", () => {
      const value = Type.integer(42);
      ApplicationEnv.put(Type.atom("my_app"), Type.atom("my_key"), value);

      const result = ApplicationEnv.get(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.atom("default"),
      );

      assert.deepStrictEqual(result, value);
    });

    it("returns default when app doesn't exist", () => {
      const defaultValue = Type.atom("default");

      const result = ApplicationEnv.get(
        Type.atom("my_app"),
        Type.atom("my_key"),
        defaultValue,
      );

      assert.deepStrictEqual(result, defaultValue);
    });

    it("returns default when key doesn't exist", () => {
      ApplicationEnv.put(
        Type.atom("my_app"),
        Type.atom("other_key"),
        Type.integer(1),
      );

      const defaultValue = Type.atom("default");

      const result = ApplicationEnv.get(
        Type.atom("my_app"),
        Type.atom("my_key"),
        defaultValue,
      );

      assert.deepStrictEqual(result, defaultValue);
    });
  });

  describe("put()", () => {
    it("stores values for different apps", () => {
      ApplicationEnv.put(Type.atom("app_1"), Type.atom("key"), Type.integer(1));
      ApplicationEnv.put(Type.atom("app_2"), Type.atom("key"), Type.integer(2));

      assert.deepStrictEqual(
        ApplicationEnv.get(Type.atom("app_1"), Type.atom("key"), Type.nil()),
        Type.integer(1),
      );

      assert.deepStrictEqual(
        ApplicationEnv.get(Type.atom("app_2"), Type.atom("key"), Type.nil()),
        Type.integer(2),
      );
    });

    it("overwrites existing value for the same app and key", () => {
      ApplicationEnv.put(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.integer(1),
      );
      ApplicationEnv.put(
        Type.atom("my_app"),
        Type.atom("my_key"),
        Type.integer(2),
      );

      assert.deepStrictEqual(
        ApplicationEnv.get(
          Type.atom("my_app"),
          Type.atom("my_key"),
          Type.nil(),
        ),
        Type.integer(2),
      );
    });
  });
});

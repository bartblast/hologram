"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import GlobalRegistry from "../../assets/js/global_registry.mjs";

defineGlobalErlangAndElixirModules();

describe("GlobalRegistry", () => {
  beforeEach(() => delete globalThis[GlobalRegistry.rootKey]);

  describe("append()", () => {
    it("key is not set", () => {
      GlobalRegistry.append("my_key", "my_value");

      assert.deepStrictEqual(GlobalRegistry.get("my_key"), ["my_value"]);
    });

    it("key is set", () => {
      GlobalRegistry.append("my_key", "my_value_1");
      GlobalRegistry.append("my_key", "my_value_2");

      assert.deepStrictEqual(GlobalRegistry.get("my_key"), [
        "my_value_1",
        "my_value_2",
      ]);
    });
  });

  describe("get()", () => {
    it("root key hasn't been set", () => {
      assert.isNull(GlobalRegistry.get("my_key"));
    });

    it("root key has already been set, but fetched key doesn't exist", () => {
      GlobalRegistry.set("my_key_1", "my_value");

      assert.isNull(GlobalRegistry.get("my_key_2"));
    });

    it("fetched key exists", () => {
      GlobalRegistry.set("my_key", "my_value");

      assert.equal(GlobalRegistry.get("my_key"), "my_value");
    });
  });

  describe("set()", () => {
    it("root key hasn't been set", () => {
      GlobalRegistry.set("my_key", "my_value");

      assert.equal(globalThis.hologram.my_key, "my_value");
    });

    it("root key has already been set", () => {
      GlobalRegistry.set("my_key", "my_value_1");
      GlobalRegistry.set("my_key", "my_value_2");

      assert.equal(globalThis.hologram.my_key, "my_value_2");
    });
  });
});

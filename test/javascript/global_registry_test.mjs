"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import GlobalRegistry from "../../assets/js/global_registry.mjs";

defineRuntimeGlobals();

describe("GlobalRegistry", () => {
  let originalHologram;

  beforeEach(() => {
    originalHologram = globalThis[GlobalRegistry.rootKey];
    delete globalThis[GlobalRegistry.rootKey];
  });

  afterEach(() => {
    globalThis[GlobalRegistry.rootKey] = originalHologram;
  });

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

      assert.equal(globalThis.Hologram.my_key, "my_value");
    });

    it("root key has already been set", () => {
      GlobalRegistry.set("my_key", "my_value_1");
      GlobalRegistry.set("my_key", "my_value_2");

      assert.equal(globalThis.Hologram.my_key, "my_value_2");
    });
  });
});

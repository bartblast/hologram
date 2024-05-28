"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Persistent_Term from "../../../assets/js/erlang/persistent_term.mjs";
import MemoryStorage from "../../../assets/js/memory_storage.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/persistent_term_test.exs
// Always update both together.

describe("Erlang_Persistent_Term", () => {
  beforeEach(() => {
    MemoryStorage.data = {};
  });

  describe("get/2", () => {
    const get = Erlang_Persistent_Term["get/2"];

    it("key exists", () => {
      const encodedKey = "tuple(atom(persistent_term),atom(my_key))";
      const value = Type.integer(123);
      MemoryStorage.put(encodedKey, value);

      const result = get(Type.atom("my_key"), Type.integer(234));

      assert.deepStrictEqual(result, value);
    });

    it("key doesn't exist", () => {
      const defaultValue = Type.integer(234);

      const result = get(Type.atom("my_key"), defaultValue);

      assert.deepStrictEqual(result, defaultValue);
    });
  });
});

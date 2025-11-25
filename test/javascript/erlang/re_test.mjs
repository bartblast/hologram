"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Re from "../../../assets/js/erlang/re.mjs";
// import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/code_test.exs
// Always update both together.

describe("Erlang_Re", () => {
  describe("version/0", () => {
    const version = Erlang_Re["version/0"];

    it("returns supported PCRE version", () => {
      const result = version();

      assert.match(result.value, /^\d+\.\d+\s+\d{4}-\d{2}-\d{2}$/);
    });
  });
});

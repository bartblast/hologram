"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Os from "../../../assets/js/erlang/os.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/os_test.exs
// Always update both together.

describe("Erlang_Os", () => {
  describe("type/0", () => {
    const type = Erlang_Os["type/0"];

    it("returns OS family and OS name", () => {
      const result = type();

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.atom("unix"), Type.atom("web")]),
      );
    });
  });
});

"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Elixir_Hologram_JS from "../../../../assets/js/elixir/hologram/js.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Hologram_JS", () => {
  describe("exec/1", () => {
    const exec = Elixir_Hologram_JS["exec/1"];

    it("delegates to Interpreter.evaluateJavaScriptCode()", () => {
      assert.deepStrictEqual(exec("1 + 2"), 3);
    });
  });
});

"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Type from "../../../../assets/js/type.mjs";
import Elixir_Hologram_JS from "../../../../assets/js/elixir/hologram/js.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Hologram_JS", () => {
  describe("exec/1", () => {
    const exec = Elixir_Hologram_JS["exec/1"];

    it("delegates to Interpreter.evaluateJavaScriptCode()", () => {
      const code = Type.bitstring("1 + 2");
      assert.deepStrictEqual(exec(code), 3);
    });
  });
});

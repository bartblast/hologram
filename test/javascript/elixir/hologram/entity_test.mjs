"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Bitstring from "../../../../assets/js/bitstring.mjs";
import Elixir_Hologram_Entity from "../../../../assets/js/elixir/hologram/entity.mjs";
import Type from "../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// The tests mirroring the Elixir tests of Hologram.Entity.generate_id/0 are NOT in this file.
// The port delegates to Utils.uuidv7(), so the mirrored tests live in test/javascript/utils_test.mjs (describe "uuidv7()").
// This file tests only the boxing wiring of the port.

describe("Elixir_Hologram_Entity", () => {
  describe("generate_id/0", () => {
    it("returns a boxed version 7 UUID string", () => {
      const result = Elixir_Hologram_Entity["generate_id/0"]();

      assert.isTrue(Type.isBitstring(result));

      assert.match(
        Bitstring.toText(result),
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    });
  });
});

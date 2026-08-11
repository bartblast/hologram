"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "../../support/helpers.mjs";

import Elixir_Hologram_Auth from "../../../../assets/js/elixir/hologram/auth.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("Elixir_Hologram_Auth", () => {
  describe("can?/3", () => {
    it("raises, since the client-side check is not implemented yet", () => {
      assertBoxedError(
        () =>
          Elixir_Hologram_Auth["can?/3"](
            Type.bitstring("0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"),
            Type.atom("read"),
            Type.map(),
          ),
        "RuntimeError",
        "can?/3 is not available on the client yet - call it from a command handler, which runs on the server",
      );
    });
  });
});

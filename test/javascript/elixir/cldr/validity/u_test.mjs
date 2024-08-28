import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../../support/helpers.mjs";

import Elixir_Cldr_Validity_U from "../../../../../assets/js/elixir/cldr/validity/u.mjs";
import HologramInterpreterError from "../../../../../assets/js/errors/interpreter_error.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Cldr_Validity_U", () => {
  it("encode_key/2", () => {
    const encode_key = Elixir_Cldr_Validity_U["encode_key/2"];

    assert.throw(
      () => encode_key("dummy_key", "dummy_value"),
      HologramInterpreterError,
      "{Cldr.Validity.U, :encode_key, 2} is not supported in Hologram.\n" +
        "See what to do here: https://www.hologram.page/TODO",
    );
  });
});

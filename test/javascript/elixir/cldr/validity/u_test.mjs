import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../../support/helpers.mjs";

import Elixir_Cldr_Validity_U from "../../../../../assets/js/elixir/cldr/validity/u.mjs";
import HologramInterpreterError from "../../../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../../../assets/js/interpreter.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Cldr_Validity_U", () => {
  it("encode_key/2", () => {
    const encode_key = Elixir_Cldr_Validity_U["encode_key/2"];

    assert.throw(
      () => encode_key("dummy_key", "dummy_value"),
      HologramInterpreterError,
      Interpreter.buildTooBigOutputErrorMsg(
        "{Cldr.Validity.U, :encode_key, 2}",
      ),
    );
  });
});

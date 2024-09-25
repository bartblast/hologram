import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import Elixir_Cldr_Locale from "../../../../assets/js/elixir/cldr/locale.mjs";
import HologramInterpreterError from "../../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../../assets/js/interpreter.mjs";

defineGlobalErlangAndElixirModules();

describe("Elixir_Cldr_Locale", () => {
  it("language_data/0", () => {
    const language_data = Elixir_Cldr_Locale["language_data/0"];

    assert.throw(
      () => language_data(),
      HologramInterpreterError,
      Interpreter.buildTooBigOutputErrorMsg("{Cldr.Locale, :language_data, 0}"),
    );
  });
});

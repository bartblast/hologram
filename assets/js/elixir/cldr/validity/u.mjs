"use strict";

import HologramInterpreterError from "../../../errors/interpreter_error.mjs";
import Interpreter from "../../../interpreter.mjs";

const Elixir_Cldr_Validity_U = {
  // TODO: port manually to JavaScript
  // {Cldr.Validity.U, :encode_key, 2} transpiles to a huge, deeply nested JS code,
  // so only a placeholder which raises an error is used here instead (temporarily).
  "encode_key/2": (_key, _value) => {
    throw new HologramInterpreterError(
      Interpreter.buildTooBigOutputErrorMsg(
        "{Cldr.Validity.U, :encode_key, 2}",
      ),
    );
  },
};

export default Elixir_Cldr_Validity_U;

"use strict";

import HologramInterpreterError from "../../../errors/interpreter_error.mjs";
import Interpreter from "../../../interpreter.mjs";

const Elixir_Cldr_Validity_U = {
  // TODO: port manually to JavaScript (transpiled output is too big and deeply nested)
  "encode_key/2": (_key, _value) => {
    throw new HologramInterpreterError(
      Interpreter.buildTooBigOutputErrorMsg(
        "{Cldr.Validity.U, :encode_key, 2}",
      ),
    );
  },
};

export default Elixir_Cldr_Validity_U;

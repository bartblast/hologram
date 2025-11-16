"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Erlang_Binary_To_Float = {
  // Start uniform/1
  "binary_to_float/1": (binary) => {
    // Must be a binary
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "expected a binary"),
      );
    }

    // Extract UTF-8 text
    const text = Bitstring.toText(binary);

    // Erlang: float literals cannot have underscores
    if (text.includes("_")) {
      Interpreter.raiseErlangError("badarg");
    }

    // OTP float literal regex (strict)
    const floatRegex = /^[+-]?\d+\.\d+([eE][+-]?\d+)?$/;

    // Must match OTP rules
    if (!floatRegex.test(text)) {
      Interpreter.raiseErlangError("badarg");
    }

    // Convert to JS float
    const value = Number(text);

    // Safety check (though regex already ensures validity)
    if (Number.isNaN(value)) {
      Interpreter.raiseErlangError("badarg");
    }

    // Return Erlang-style float term
    return Type.float(value);
  },
  // End uniform/1
  // Deps: []
};

export default Erlang_Binary_To_Float;

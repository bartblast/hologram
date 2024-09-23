"use strict";

import Bitstring from "../bitstring.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_String = {
  // Deps: [String.downcase/2]
  "downcase/1": (string) => {
    return Elixir_String["downcase/2"](string, Type.atom("default"));
  },

  // TODO: support mode param (see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/toLocaleLowerCase)
  "downcase/2": function (string, mode) {
    const allowedModes = ["default", "ascii", "greek", "turkic"];

    if (
      !Type.isBinary(string) ||
      !Type.isAtom(mode) ||
      !allowedModes.includes(mode.value)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", arguments),
      );
    }

    if (mode.value !== "default") {
      throw new HologramInterpreterError(
        "String.downcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(Bitstring.toText(string).toLowerCase());
  },

  // Deps: [String.upcase/2]
  "upcase/1": (string) => {
    return Elixir_String["upcase/2"](string, Type.atom("default"));
  },

  // TODO: support mode param (see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/toLocaleUpperCase)
  "upcase/2": function (string, mode) {
    const allowedModes = ["default", "ascii", "greek", "turkic"];

    if (
      !Type.isBinary(string) ||
      !Type.isAtom(mode) ||
      !allowedModes.includes(mode.value)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", arguments),
      );
    }

    if (mode.value !== "default") {
      throw new HologramInterpreterError(
        "String.upcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(Bitstring.toText(string).toUpperCase());
  },
};

export default Elixir_String;

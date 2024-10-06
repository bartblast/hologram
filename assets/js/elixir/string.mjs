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

  "replace/3": function (subject, pattern, replacement) {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.replace/4", arguments),
      );
    }

    if (!Type.isBinary(pattern) || pattern.bits.length === 0) {
      throw new HologramInterpreterError(
        "using String.replace/3 pattern argument other than non-empty binary is not yet implemented in Hologram",
      );
    }

    if (!Type.isBinary(replacement)) {
      throw new HologramInterpreterError(
        "using String.replace/3 replacement argument other than binary is not yet implemented in Hologram",
      );
    }

    const subjectStr = Bitstring.toText(subject);
    const patternStr = Bitstring.toText(pattern);
    const replacementStr = Bitstring.toText(replacement);

    return Type.bitstring(subjectStr.replaceAll(patternStr, replacementStr));
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

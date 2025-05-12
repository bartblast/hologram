"use strict";

import Bitstring2 from "../bitstring2.mjs";
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
    const modeValue = mode.value;

    if (
      !Type.isBinary2(string) ||
      !Type.isAtom(mode) ||
      (modeValue !== "default" &&
        modeValue !== "ascii" &&
        modeValue !== "greek" &&
        modeValue !== "turkic")
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.downcase/2", arguments),
      );
    }

    if (modeValue !== "default") {
      throw new HologramInterpreterError(
        "String.downcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring2(Bitstring2.toText(string).toLowerCase());
  },

  "replace/3": function (subject, pattern, replacement) {
    if (!Type.isBinary2(subject)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.replace/4", arguments),
      );
    }

    if (!Type.isBinary2(pattern) || pattern.bits.length === 0) {
      throw new HologramInterpreterError(
        "using String.replace/3 pattern argument other than non-empty binary is not yet implemented in Hologram",
      );
    }

    if (!Type.isBinary2(replacement)) {
      throw new HologramInterpreterError(
        "using String.replace/3 replacement argument other than binary is not yet implemented in Hologram",
      );
    }

    const subjectStr = Bitstring2.toText(subject);
    const patternStr = Bitstring2.toText(pattern);
    const replacementStr = Bitstring2.toText(replacement);

    return Type.bitstring2(subjectStr.replaceAll(patternStr, replacementStr));
  },

  // Deps: [String.upcase/2]
  "upcase/1": (string) => {
    return Elixir_String["upcase/2"](string, Type.atom("default"));
  },

  // TODO: support mode param (see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/toLocaleUpperCase)
  "upcase/2": function (string, mode) {
    const modeValue = mode.value;

    if (
      !Type.isBinary2(string) ||
      !Type.isAtom(mode) ||
      (modeValue !== "default" &&
        modeValue !== "ascii" &&
        modeValue !== "greek" &&
        modeValue !== "turkic")
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("String.upcase/2", arguments),
      );
    }

    if (modeValue !== "default") {
      throw new HologramInterpreterError(
        "String.upcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring2(Bitstring2.toText(string).toUpperCase());
  },
};

export default Elixir_String;

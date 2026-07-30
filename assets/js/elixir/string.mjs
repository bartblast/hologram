"use strict";

import Bitstring from "../bitstring.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_String = {
  "contains?/2": (subject, patternOrPatterns) => {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseFunctionClauseError("String", "contains?", 2, [
        subject,
        patternOrPatterns,
      ]);
    }

    const subjectText = Bitstring.toText(subject);

    if (Type.isBinary(patternOrPatterns)) {
      const patternText = Bitstring.toText(patternOrPatterns);
      return Type.boolean(subjectText.includes(patternText));
    }

    if (Type.isList(patternOrPatterns)) {
      const patternCount = patternOrPatterns.data.length;
      let result = false;

      for (let i = 0; i < patternCount; i++) {
        const pattern = patternOrPatterns.data[i];

        // The server sizes each pattern element first, so a non-bitstring
        // fails in the byte_size BIF.
        if (!Type.isBitstring(pattern)) {
          Interpreter.raiseBifError("badarg", "erlang", "byte_size", [pattern]);
        }

        // The server searches with binary:match/2, so an invalid pattern
        // reports that identity with the whole pattern list.
        if (!Type.isBinary(pattern)) {
          Interpreter.raiseBifError("badarg", "binary", "match", [
            subject,
            patternOrPatterns,
          ]);
        }

        const patternText = Bitstring.toText(pattern);

        if (subjectText.includes(patternText)) {
          result = true;
        }
      }

      return Type.boolean(result);
    }

    if (Type.isCompiledPattern(patternOrPatterns)) {
      throw new HologramInterpreterError(
        "String.contains?/2 with compiled patterns is not yet implemented in Hologram",
      );
    }

    // The server searches with binary:match/2, so an invalid pattern
    // reports that identity.
    Interpreter.raiseBifError("badarg", "binary", "match", [
      subject,
      patternOrPatterns,
    ]);
  },

  // Deps: [String.downcase/2]
  "downcase/1": (string) => {
    return Elixir_String["downcase/2"](string, Type.atom("default"));
  },

  // TODO: support mode param (see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/toLocaleLowerCase)
  "downcase/2": function (string, mode) {
    const modeValue = mode.value;

    if (
      !Type.isBinary(string) ||
      !Type.isAtom(mode) ||
      (modeValue !== "default" &&
        modeValue !== "ascii" &&
        modeValue !== "greek" &&
        modeValue !== "turkic")
    ) {
      Interpreter.raiseFunctionClauseError("String", "downcase", 2, [
        string,
        mode,
      ]);
    }

    if (modeValue !== "default") {
      throw new HologramInterpreterError(
        "String.downcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(Bitstring.toText(string).toLowerCase());
  },

  "replace/3": function (subject, pattern, replacement) {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseFunctionClauseError("String", "replace", 4, [
        subject,
        pattern,
        replacement,
        Type.list(),
      ]);
    }

    if (!Type.isBinary(pattern) || Bitstring.isEmpty(pattern)) {
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

  "trim/1": function (string) {
    if (!Type.isBinary(string)) {
      Interpreter.raiseFunctionClauseError("String", "trim", 1, [string]);
    }

    // TODO: handle non-textual binary data (text is null)
    return Type.bitstring(Bitstring.toText(string).trim());
  },

  // Deps: [String.upcase/2]
  "upcase/1": (string) => {
    return Elixir_String["upcase/2"](string, Type.atom("default"));
  },

  // TODO: support mode param (see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/toLocaleUpperCase)
  "upcase/2": function (string, mode) {
    const modeValue = mode.value;

    if (
      !Type.isBinary(string) ||
      !Type.isAtom(mode) ||
      (modeValue !== "default" &&
        modeValue !== "ascii" &&
        modeValue !== "greek" &&
        modeValue !== "turkic")
    ) {
      Interpreter.raiseFunctionClauseError("String", "upcase", 2, [
        string,
        mode,
      ]);
    }

    if (modeValue !== "default") {
      throw new HologramInterpreterError(
        "String.upcase/2 modes other than :default are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(Bitstring.toText(string).toUpperCase());
  },
};

export default Elixir_String;

"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

function toString(input) {
  if (Type.isBinary(input)) {
    Bitstring.maybeSetBytesFromText(input);
    return new TextDecoder("utf-8").decode(input.bytes);
  } else if (Type.isList(input)) {
    const chars = input.data.map((elem) => {
      if (!Type.isInteger(elem)) {
        throw new Error("not a valid string");
      }
      return String.fromCharCode(Number(elem.value));
    });
    return chars.join("");
  } else {
    throw new Error("not a valid string");
  }
}

const Erlang_Elixir_Utils = {
  // Start jaro_similarity/2
  "jaro_similarity/2": (string1, string2) => {
    try {
      const s1 = toString(string1);
      const s2 = toString(string2);

      // Handle empty strings
      if (s1.length === 0 && s2.length === 0) {
        return Type.float(1.0);
      }
      if (s1.length === 0 || s2.length === 0) {
        return Type.float(0.0);
      }

      // Calculate match window
      const matchWindow = Math.floor(Math.max(s1.length, s2.length) / 2) - 1;
      if (matchWindow < 0) {
        return Type.float(0.0);
      }

      // Track matched characters
      const s1Matches = new Array(s1.length).fill(false);
      const s2Matches = new Array(s2.length).fill(false);

      let matches = 0;

      // Find matches
      for (let i = 0; i < s1.length; i++) {
        const start = Math.max(0, i - matchWindow);
        const end = Math.min(i + matchWindow + 1, s2.length);

        for (let j = start; j < end; j++) {
          if (s2Matches[j] || s1[i] !== s2[j]) {
            continue;
          }

          s1Matches[i] = true;
          s2Matches[j] = true;
          matches++;
          break;
        }
      }

      if (matches === 0) {
        return Type.float(0.0);
      }

      // Count transpositions
      let transpositions = 0;
      let k = 0;

      for (let i = 0; i < s1.length; i++) {
        if (!s1Matches[i]) {
          continue;
        }

        while (!s2Matches[k]) {
          k++;
        }

        if (s1[i] !== s2[k]) {
          transpositions++;
        }

        k++;
      }

      // Calculate Jaro similarity
      const jaro =
        (matches / s1.length +
          matches / s2.length +
          (matches - transpositions / 2) / matches) /
        3;

      return Type.float(jaro);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End jaro_similarity/2
  // Deps: []
};

export default Erlang_Elixir_Utils;

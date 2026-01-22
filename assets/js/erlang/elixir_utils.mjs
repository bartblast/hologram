"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Utils = {
  // Start jaro_similarity/2
  "jaro_similarity/2": (str1, str2) => {
    // Helper: Extract code points from a bitstring or list (including nested lists)
    const extractCodePoints = (str) => {
      if (Type.isBitstring(str)) {
        Bitstring.maybeSetTextFromBytes(str);
        return Array.from(str.text).map((c) => c.charCodeAt(0));
      } else if (Type.isList(str)) {
        const codePoints = [];
        for (let i = 0; i < str.data.length; i++) {
          const n = str.data[i];

          if (Type.isInteger(n)) {
            codePoints.push(Number(n.value));
          } else if (Type.isBitstring(n)) {
            Bitstring.maybeSetTextFromBytes(n);
            codePoints.push(n.text.charCodeAt(0));
          } else if (Type.isList(n) && n.data.length > 0) {
            const firstElem = n.data[0];
            if (Type.isInteger(firstElem)) {
              codePoints.push(Number(firstElem.value));
            } else if (Type.isBitstring(firstElem)) {
              Bitstring.maybeSetTextFromBytes(firstElem);
              codePoints.push(firstElem.text.charCodeAt(0));
            }
          } else {
            if (str.data.length > 1) {
              const remaining = Type.list(str.data.slice(i + 1));
              Interpreter.raiseFunctionClauseError(
                Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl/2", [
                  n,
                  remaining,
                ]),
              );
            } else {
              Interpreter.raiseFunctionClauseError(
                Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
                  n,
                ]),
              );
            }
          }
        }
        return codePoints;
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [str]),
        );
      }
    };

    const codePoints1 = extractCodePoints(str1);
    const codePoints2 = extractCodePoints(str2);

    const len1 = codePoints1.length;
    const len2 = codePoints2.length;

    if (len1 === 0 && len2 === 0) {
      return Type.float(1.0);
    }

    if (len1 === 0 || len2 === 0) {
      return Type.float(0.0);
    }

    // Known issue in :elixir_utils.jaro_similarity/2 that will be fixed when Elixir requires Erlang/OTP 27+ and switches to :string.jaro_similarity/2
    if (len1 === 1 && len2 === 1) {
      return Type.float(0.0);
    }

    const matchWindow = Math.max(Math.floor(Math.max(len1, len2) / 2) - 1, 0);
    const matches1 = new Array(len1).fill(false);
    const matches2 = new Array(len2).fill(false);
    let matchCount = 0;

    for (let i = 0; i < len1; i++) {
      const start = Math.max(0, i - matchWindow);
      const end = Math.min(i + matchWindow + 1, len2);

      for (let j = start; j < end; j++) {
        if (!matches2[j] && codePoints1[i] === codePoints2[j]) {
          matches1[i] = true;
          matches2[j] = true;
          matchCount++;
          break;
        }
      }
    }

    if (matchCount === 0) {
      return Type.float(0.0);
    }

    let transpositions = 0;
    let k = 0;

    for (let i = 0; i < len1; i++) {
      if (matches1[i]) {
        while (!matches2[k]) k++;
        if (codePoints1[i] !== codePoints2[k]) {
          transpositions++;
        }
        k++;
      }
    }

    const similarity =
      (matchCount / len1 +
        matchCount / len2 +
        (matchCount - transpositions / 2) / matchCount) /
      3;

    return Type.float(similarity);
  },
  // End jaro_similarity/2
  // Deps: []
};

export default Erlang_Elixir_Utils;

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
    const extractCodePoints = (str) => {
      if (Type.isBitstring(str)) {
        const text = Bitstring.toText(str);

        if (text === false) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, Interpreter.inspect(str)),
          );
        }

        return Array.from(text).map((c) => c.codePointAt(0));
      }

      if (Type.isList(str)) {
        const codePoints = [];

        for (let i = 0; i < str.data.length; i++) {
          const elem = str.data[i];

          if (Type.isInteger(elem)) {
            codePoints.push(Number(elem.value));
            continue;
          }

          if (Type.isBitstring(elem)) {
            const text = Bitstring.toText(elem);

            if (text === false) {
              Interpreter.raiseArgumentError(
                Interpreter.buildArgumentErrorMsg(1, Interpreter.inspect(elem)),
              );
            }

            codePoints.push(text.codePointAt(0));
            continue;
          }

          if (Type.isList(elem) && elem.data.length > 0) {
            const firstElem = elem.data[0];

            if (Type.isInteger(firstElem)) {
              codePoints.push(Number(firstElem.value));
              continue;
            }

            if (Type.isBitstring(firstElem)) {
              const text = Bitstring.toText(firstElem);

              if (text === false) {
                Interpreter.raiseArgumentError(
                  Interpreter.buildArgumentErrorMsg(
                    1,
                    Interpreter.inspect(firstElem),
                  ),
                );
              }

              codePoints.push(text.codePointAt(0));
              continue;
            }
          }

          const isMultiElement = str.data.length > 1;
          const funcName = isMultiElement
            ? ":unicode_util.cpl/2"
            : ":unicode_util.cp/1";
          const args = isMultiElement
            ? [elem, Type.list(str.data.slice(i + 1))]
            : [elem];

          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(funcName, args),
          );
        }

        return codePoints;
      }

      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [str]),
      );
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

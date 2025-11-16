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

const Erlang_Unicode_Util = {
  // Start gc/1
  "gc/1": (charDataOrString) => {
    try {
      // Convert input to string
      let str;
      let returnAsList = false;

      if (Type.isBinary(charDataOrString)) {
        str = toString(charDataOrString);
      } else if (Type.isList(charDataOrString)) {
        // Check if it's a string (list of integers) or a list of codepoints
        if (charDataOrString.data.length === 0) {
          return Type.list([]);
        }

        str = toString(charDataOrString);
        returnAsList = true;
      } else {
        Interpreter.raiseArgumentError("argument error");
        return;
      }

      if (str.length === 0) {
        return returnAsList ? Type.list([]) : Type.list([]);
      }

      // Use Intl.Segmenter to get grapheme clusters if available
      let graphemes;

      if (typeof Intl !== "undefined" && Intl.Segmenter) {
        const segmenter = new Intl.Segmenter("en", {granularity: "grapheme"});
        const segments = [...segmenter.segment(str)];
        graphemes = segments.map((s) => s.segment);
      } else {
        // Fallback: treat each character as a grapheme
        graphemes = [...str];
      }

      if (graphemes.length === 0) {
        return returnAsList ? Type.list([]) : Type.list([]);
      }

      // Get first grapheme cluster
      const firstGrapheme = graphemes[0];
      const remainingStr = graphemes.slice(1).join("");

      // Convert first grapheme to list of codepoints
      const codepoints = [...firstGrapheme].map((char) =>
        Type.integer(char.codePointAt(0)),
      );

      // Build result: [FirstGrapheme, RestOfString]
      if (returnAsList) {
        // Return as list of codepoints
        if (remainingStr.length > 0) {
          const restCodepoints = [...remainingStr].map((char) =>
            Type.integer(char.codePointAt(0)),
          );
          return Type.list([Type.list(codepoints), Type.list(restCodepoints)]);
        } else {
          return Type.list([Type.list(codepoints)]);
        }
      } else {
        // Return as binary
        const firstGraphemeBinary = Type.bitstring(
          new TextEncoder().encode(firstGrapheme),
          0,
        );

        if (remainingStr.length > 0) {
          const restBinary = Type.bitstring(
            new TextEncoder().encode(remainingStr),
            0,
          );
          return Type.list([firstGraphemeBinary, restBinary]);
        } else {
          return Type.list([firstGraphemeBinary]);
        }
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End gc/1
  // Deps: []
};

export default Erlang_Unicode_Util;

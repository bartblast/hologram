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

function toBinary(str) {
  const bytes = new TextEncoder().encode(str);
  return Type.bitstring(bytes, 0);
}

const Erlang_String = {
  // Start find/2
  "find/2": (string, searchPattern) => {
    try {
      const str = toString(string);
      const pattern = toString(searchPattern);

      const index = str.indexOf(pattern);

      if (index === -1) {
        return Type.atom("nomatch");
      }

      // Return the part of the string from the match onward
      const result = str.substring(index);
      return toBinary(result);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End find/2
  // Deps: []

  // Start join/2
  "join/2": (stringList, separator) => {
    if (!Type.isList(stringList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    try {
      const strings = stringList.data.map((s) => toString(s));
      const sep = toString(separator);

      const result = strings.join(sep);
      return toBinary(result);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End join/2
  // Deps: []

  // Start length/1
  "length/1": (string) => {
    try {
      const str = toString(string);

      // Count grapheme clusters using Intl.Segmenter if available
      // Fallback to character count
      if (typeof Intl !== "undefined" && Intl.Segmenter) {
        const segmenter = new Intl.Segmenter("en", {granularity: "grapheme"});
        const segments = [...segmenter.segment(str)];
        return Type.integer(segments.length);
      } else {
        // Fallback: count characters (not perfect for complex graphemes)
        return Type.integer([...str].length);
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End length/1
  // Deps: []

  // Start replace/4
  "replace/4": (string, searchPattern, replacement, where) => {
    if (!Type.isAtom(where)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(4, "not an atom"),
      );
    }

    try {
      const str = toString(string);
      const pattern = toString(searchPattern);
      const replace = toString(replacement);
      const whereValue = where.value;

      let result;

      switch (whereValue) {
        case "leading":
          // Replace only at the beginning
          if (str.startsWith(pattern)) {
            result = replace + str.substring(pattern.length);
          } else {
            result = str;
          }
          break;

        case "trailing":
          // Replace only at the end
          if (str.endsWith(pattern)) {
            result = str.substring(0, str.length - pattern.length) + replace;
          } else {
            result = str;
          }
          break;

        case "all":
          // Replace all occurrences
          result = str.split(pattern).join(replace);
          break;

        default:
          Interpreter.raiseArgumentError("argument error");
          return;
      }

      return toBinary(result);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End replace/4
  // Deps: []
};

export default Erlang_String;

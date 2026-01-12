"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_String = {
  // Start titlecase/1
  "titlecase/1": (subject) => {
    // Custom uppercase mapping where Erlang differs from JavaScript's toUpperCase()
    // This mapping is extracted from scripts/uppercase_mapping/comparison.txt
    // Format: { codepoint: [codepoints] }
    const MAPPING = {
      223: [83, 115],
      411: [411],
      452: [453],
      453: [453],
      454: [453],
      455: [456],
      456: [456],
      457: [456],
      458: [459],
      459: [459],
      460: [459],
      497: [498],
      498: [498],
      499: [498],
      612: [612],
      1415: [1333, 1410],
      4349: [4349],
      4350: [4350],
      4351: [4351],
      7306: [7306],
      8064: [8072],
      8065: [8073],
      8066: [8074],
      8067: [8075],
      8068: [8076],
      8069: [8077],
      8070: [8078],
      8071: [8079],
      8080: [8088],
      8081: [8089],
      8082: [8090],
      8083: [8091],
      8084: [8092],
      8085: [8093],
      8086: [8094],
      8087: [8095],
      8096: [8104],
      8097: [8105],
      8098: [8106],
      8099: [8107],
      8100: [8108],
      8101: [8109],
      8102: [8110],
      8103: [8111],
      8114: [8122, 837],
      8115: [8124],
      8116: [902, 837],
      8119: [913, 834, 837],
      8124: [8124],
      8130: [8138, 837],
      8131: [8140],
      8132: [905, 837],
      8135: [919, 834, 837],
      8140: [8140],
      8178: [8186, 837],
      8179: [8188],
      8180: [911, 837],
      8183: [937, 834, 837],
      8188: [8188],
      42957: [42957],
      42971: [42971],
      64256: [70, 102],
      64257: [70, 105],
      64258: [70, 108],
      64259: [70, 102, 105],
      64260: [70, 102, 108],
      64261: [83, 116],
      64262: [83, 116],
      64275: [1348, 1398],
      64276: [1348, 1381],
      64277: [1348, 1387],
      64278: [1358, 1398],
      64279: [1348, 1389],
    };

    // Helper: Check if a list contains only integers
    const containsOnlyIntegers = (data) => {
      return data.every((item) => Type.isInteger(item));
    };

    // Helper: Extract first character and rest from text string
    const extractFirstChar = (text) => {
      const firstChar = Array.from(text)[0];
      const firstCodePoint = firstChar.codePointAt(0);
      const restOfString = text.slice(firstChar.length);
      return {firstCodePoint, restOfString};
    };

    // Helper: Uppercase a single codepoint and return array of uppercased codepoints
    const uppercaseCodepoint = (codepoint) => {
      if (
        (codepoint >= 4304 && codepoint <= 4346) ||
        (codepoint >= 8072 && codepoint <= 8079) ||
        (codepoint >= 8088 && codepoint <= 8095) ||
        (codepoint >= 8104 && codepoint <= 8111) ||
        (codepoint >= 68976 && codepoint <= 68997)
      ) {
        return [codepoint];
      } else if (Object.hasOwn(MAPPING, codepoint)) {
        return MAPPING[codepoint];
      } else {
        const char = String.fromCodePoint(codepoint);
        const uppercased = char.toUpperCase();
        return Array.from(uppercased).map((c) => c.codePointAt(0));
      }
    };

    // Helper: Validate codepoint is not in surrogate pair range
    const validateCodepoint = (codepoint) => {
      // Check if the codepoint is in the invalid range (55296-57343 / 0xD800-0xDFFF)
      // These are not valid Unicode scalar values and cannot be encoded in UTF-8
      if (codepoint >= 55296 && codepoint <= 57343) {
        Interpreter.raiseArgumentError(
          `argument error: ${Interpreter.inspect(subject)}`,
        );
      }
    };

    // Handle binary strings
    if (Type.isBinary(subject)) {
      const text = Bitstring.toText(subject);

      if (text === false) {
        Interpreter.raiseArgumentError(
          `argument error: ${Interpreter.inspect(subject)}`,
        );
      }

      if (text.length === 0) {
        return Type.bitstring("");
      }

      const {firstCodePoint, restOfString} = extractFirstChar(text);
      validateCodepoint(firstCodePoint);

      const uppercasedCodepoints = uppercaseCodepoint(firstCodePoint);
      const uppercasedFirst = String.fromCodePoint(...uppercasedCodepoints);

      return Type.bitstring(uppercasedFirst + restOfString);
    }

    // Handle lists (charlists/iolists)
    if (Type.isList(subject)) {
      if (subject.data.length === 0) {
        return Type.list();
      }

      const firstElement = subject.data[0];
      const rest = subject.data.slice(1);

      // If first element is an integer codepoint
      if (Type.isInteger(firstElement)) {
        const codepoint = Number(firstElement.value);
        validateCodepoint(codepoint);

        const uppercasedCodepoints = uppercaseCodepoint(codepoint).map((cp) =>
          Type.integer(cp),
        );

        return Type.list([...uppercasedCodepoints, ...rest]);
      }

      // If first element is a binary string
      if (Type.isBinary(firstElement)) {
        const text = Bitstring.toText(firstElement);

        if (text === false) {
          Interpreter.raiseArgumentError(
            `argument error: ${Interpreter.inspect(subject)}`,
          );
        }

        if (text.length === 0) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
              subject,
            ]),
          );
        }

        const {firstCodePoint, restOfString} = extractFirstChar(text);
        validateCodepoint(firstCodePoint);

        const uppercasedCodepoints = uppercaseCodepoint(firstCodePoint).map(
          (cp) => Type.integer(cp),
        );

        const result = [...uppercasedCodepoints];

        if (restOfString.length > 0) {
          result.push(Type.bitstring(restOfString));
        }

        result.push(...rest);

        return Type.list(result);
      }

      // If first element is a nested list, recursively process it
      if (Type.isList(firstElement)) {
        const processedFirst = Erlang_String["titlecase/1"](firstElement);
        const processedData = processedFirst.data;

        // Combine the processed first element with the rest using these rules:
        // 1. If both contain only integers, spread both
        // 2. If rest starts with a binary, spread processedData, add binary, wrap remainder
        // 3. If processedData contains non-integers and rest has multiple elements, wrap rest
        // 4. Otherwise, spread both

        if (rest.length === 0) {
          return Type.list(processedData);
        }

        // Rule 1: Both contain only integers
        if (containsOnlyIntegers(processedData) && containsOnlyIntegers(rest)) {
          return Type.list([...processedData, ...rest]);
        }

        // Rule 2: Rest starts with a binary
        if (Type.isBinary(rest[0])) {
          const result = [...processedData, rest[0]];

          if (rest.length > 1) {
            result.push(Type.list(rest.slice(1)));
          }

          return Type.list(result);
        }

        // Rule 3: processedData contains non-integers and rest has multiple elements
        if (!containsOnlyIntegers(processedData) && rest.length > 1) {
          return Type.list([...processedData, Type.list(rest)]);
        }

        // Rule 4: Default - spread both
        return Type.list([...processedData, ...rest]);
      }

      // If first element is neither integer nor binary nor list, raise FunctionClauseError
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
          subject,
        ]),
      );
    }

    // If subject is neither binary nor list, raise FunctionClauseError
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [subject]),
    );
  },
  // End titlecase/1
  // Deps: []
};

export default Erlang_String;

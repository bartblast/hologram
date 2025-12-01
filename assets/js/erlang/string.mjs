"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_UnicodeUtil from "./unicode_util.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_String = {
  // Start join/2
  "join/2": function (list, separator) {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.join/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(
          `{:bad_generator, ${Interpreter.inspect(list.data.at(-1))}}`,
        ),
      );
    }

    if (list.data.length === 0) {
      if (!Type.isProperList(separator)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", arguments),
        );
      }

      return Type.list();
    }

    // Single element case - return element as-is (separator not used, no validation needed)
    if (list.data.length === 1) {
      const element = list.data[0];

      if (!Type.isList(element)) {
        Interpreter.raiseArgumentError("argument error");
      }

      return element;
    }

    // Multiple elements - validate separator is a list (for concatenation)
    if (!Type.isList(separator)) {
      Interpreter.raiseArgumentError("argument error");
    }

    // Join the strings with separator
    const result = [];

    for (let i = 0; i < list.data.length; i++) {
      const element = list.data[i];

      // Each element must be a list (for concatenation)
      if (!Type.isList(element)) {
        Interpreter.raiseArgumentError("argument error");
      }

      if (i > 0) {
        result.push(...separator.data);
      }

      result.push(...element.data);
    }

    return Type.list(result);
  },
  // End join/2
  // Deps: []

  // Start replace/3
  "replace/3": (string, pattern, replacement) => {
    const replace = Erlang_String["replace/4"];

    return replace(string, pattern, replacement, Type.atom("leading"));
  },
  // End replace/3
  // Deps: [:string.replace/4]

  // Start replace/4
  "replace/4": (string, pattern, replacement, direction) => {
    if (!Type.isBinary(string)) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(string));
    }

    if (!Type.isBinary(pattern)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    }

    if (!Type.isBinary(replacement)) {
      throw new HologramInterpreterError(
        "using :string.replace/3 or :string.replace/4 replacement argument other than binary is not yet implemented in Hologram",
      );
    }

    if (!Type.isAtom(direction)) {
      Interpreter.raiseCaseClauseError(direction);
    }

    const stringText = Bitstring.toText(string);
    const patternText = Bitstring.toText(pattern);
    const replacementText = Bitstring.toText(replacement);

    if (Bitstring.isEmpty(pattern) || !stringText.includes(patternText)) {
      return Type.list([string]);
    }

    let splittedStringList, index;
    switch (direction.value) {
      case "all":
        splittedStringList = stringText
          .split(patternText)
          .flatMap((elem, index) => {
            return index === 0 ? elem : [replacementText, elem];
          });
        break;

      case "trailing":
        index = stringText.lastIndexOf(patternText);
        splittedStringList = [
          stringText.slice(0, index),
          replacementText,
          stringText.slice(index + patternText.length),
        ];
        break;

      case "leading":
      default:
        index = stringText.indexOf(patternText);
        splittedStringList = [
          stringText.slice(0, index),
          replacementText,
          stringText.slice(index + patternText.length),
        ];
        break;
    }

    return Type.list(splittedStringList);
  },
  // End replace/4
  // Deps: []

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

    // Helper: Extract first codepoint using unicode_util.cp/1
    const extractFirstCodepoint = (subject) => {
      const cpResult = Erlang_UnicodeUtil["cp/1"](subject);

      // Check if unicode_util.cp/1 returned an error tuple
      if (Type.isTuple(cpResult)) {
        // Extract the binary from the error tuple {:error, binary}
        const errorBinary = cpResult.data[1];
        Interpreter.raiseArgumentError(
          `argument error: ${Interpreter.inspect(errorBinary)}`,
        );
      }

      // Return null for empty results
      if (cpResult.data.length === 0) {
        return null;
      }

      // Extract codepoint number and rest
      const firstCodepoint = cpResult.data[0];
      const codepointNum = Number(firstCodepoint.value);
      const rest = cpResult.data.slice(1);

      return { codepointNum, rest };
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

    // Handle binary strings
    if (Type.isBinary(subject)) {
      const extraction = extractFirstCodepoint(subject);

      if (extraction === null) {
        return Type.bitstring("");
      }

      const { codepointNum, rest } = extraction;
      const restBinary = rest[0]; // Tail of the improper list
      const restText = Bitstring.toText(restBinary);

      const uppercasedCodepoints = uppercaseCodepoint(codepointNum);
      const uppercasedFirst = String.fromCodePoint(...uppercasedCodepoints);

      return Type.bitstring(uppercasedFirst + restText);
    }

    // Handle lists (charlists/iolists)
    if (Type.isList(subject)) {
      const extraction = extractFirstCodepoint(subject);

      if (extraction === null) {
        return Type.list();
      }

      const { codepointNum, rest } = extraction;
      const uppercasedCodepoints = uppercaseCodepoint(codepointNum).map((cp) =>
        Type.integer(cp),
      );

      const firstRest = rest.length > 0 ? rest[0] : null;

      // Check for ligature grouping: ligatures (64256-64262) that expand to multiple
      // codepoints should be grouped when followed by a non-empty binary
      const isLigature = codepointNum >= 64_256 && codepointNum <= 64_262;
      if (
        isLigature &&
        uppercasedCodepoints.length > 1 &&
        firstRest &&
        Type.isBitstring(firstRest) &&
        firstRest.text.length > 0
      ) {
        return Type.list([Type.list(uppercasedCodepoints), ...rest]);
      }

      // Filter out empty binary at the end (for improper list tails)
      if (
        rest.length === 1 &&
        Type.isBitstring(firstRest) &&
        firstRest.text.length === 0
      ) {
        return Type.list([...uppercasedCodepoints]);
      }

      // Default: combine uppercased codepoint(s) with the rest
      return Type.list([...uppercasedCodepoints, ...rest]);
    }

    // If subject is neither binary nor list, raise FunctionClauseError
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [subject]),
    );
  },
  // End titlecase/1
  // Deps: [:unicode_util.cp/1]
};

export default Erlang_String;

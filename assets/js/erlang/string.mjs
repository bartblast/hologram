"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_UnicodeUtil from "./unicode_util.mjs";
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

      return {codepointNum, rest};
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

      const {codepointNum, rest} = extraction;
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

      const {codepointNum, rest} = extraction;
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

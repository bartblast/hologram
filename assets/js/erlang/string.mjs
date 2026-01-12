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
      4304: [4304],
      4305: [4305],
      4306: [4306],
      4307: [4307],
      4308: [4308],
      4309: [4309],
      4310: [4310],
      4311: [4311],
      4312: [4312],
      4313: [4313],
      4314: [4314],
      4315: [4315],
      4316: [4316],
      4317: [4317],
      4318: [4318],
      4319: [4319],
      4320: [4320],
      4321: [4321],
      4322: [4322],
      4323: [4323],
      4324: [4324],
      4325: [4325],
      4326: [4326],
      4327: [4327],
      4328: [4328],
      4329: [4329],
      4330: [4330],
      4331: [4331],
      4332: [4332],
      4333: [4333],
      4334: [4334],
      4335: [4335],
      4336: [4336],
      4337: [4337],
      4338: [4338],
      4339: [4339],
      4340: [4340],
      4341: [4341],
      4342: [4342],
      4343: [4343],
      4344: [4344],
      4345: [4345],
      4346: [4346],
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
      8072: [8072],
      8073: [8073],
      8074: [8074],
      8075: [8075],
      8076: [8076],
      8077: [8077],
      8078: [8078],
      8079: [8079],
      8080: [8088],
      8081: [8089],
      8082: [8090],
      8083: [8091],
      8084: [8092],
      8085: [8093],
      8086: [8094],
      8087: [8095],
      8088: [8088],
      8089: [8089],
      8090: [8090],
      8091: [8091],
      8092: [8092],
      8093: [8093],
      8094: [8094],
      8095: [8095],
      8096: [8104],
      8097: [8105],
      8098: [8106],
      8099: [8107],
      8100: [8108],
      8101: [8109],
      8102: [8110],
      8103: [8111],
      8104: [8104],
      8105: [8105],
      8106: [8106],
      8107: [8107],
      8108: [8108],
      8109: [8109],
      8110: [8110],
      8111: [8111],
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
      68976: [68976],
      68977: [68977],
      68978: [68978],
      68979: [68979],
      68980: [68980],
      68981: [68981],
      68982: [68982],
      68983: [68983],
      68984: [68984],
      68985: [68985],
      68986: [68986],
      68987: [68987],
      68988: [68988],
      68989: [68989],
      68990: [68990],
      68991: [68991],
      68992: [68992],
      68993: [68993],
      68994: [68994],
      68995: [68995],
      68996: [68996],
      68997: [68997],
    };

    // Helper: Check if a list contains only integers
    const containsOnlyIntegers = (data) => {
      return data.every((item) => Type.isInteger(item));
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

    // Helper: Uppercase a single codepoint and return array of uppercased codepoints
    const uppercaseCodepoint = (codepoint) => {
      if (Object.hasOwn(MAPPING, codepoint)) {
        return MAPPING[codepoint];
      } else {
        const char = String.fromCodePoint(codepoint);
        const uppercased = char.toUpperCase();
        return Array.from(uppercased).map((c) => c.codePointAt(0));
      }
    };

    // Helper: Extract first character and rest from text string
    const extractFirstChar = (text) => {
      const firstChar = Array.from(text)[0];
      const firstCodePoint = firstChar.codePointAt(0);
      const restOfString = text.slice(firstChar.length);
      return {firstCodePoint, restOfString};
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
            Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1 ", [
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

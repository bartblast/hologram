"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Unicode from "./unicode.mjs";
import Erlang_Unicode_Util from "./unicode_util.mjs";
import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_String = {
  // Start find/2
  "find/2": (string, searchPattern) => {
    return Erlang_String["find/3"](string, searchPattern, Type.atom("leading"));
  },
  // End find/2
  // Deps: [:string.find/3]

  // Start find/3
  "find/3": (string, searchPattern, direction) => {
    let stringBinary;

    try {
      stringBinary = Erlang_Unicode["characters_to_binary/1"](string);
    } catch {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(string));
    }

    if (Type.isTuple(stringBinary)) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(string));
    }

    const patternBinary =
      Erlang_Unicode["characters_to_binary/1"](searchPattern);

    if (Type.isTuple(patternBinary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    }

    if (!Type.isAtom(direction)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.find/3", [
          string,
          searchPattern,
          direction,
        ]),
      );
    }

    const directionValue = direction.value;

    if (!["leading", "trailing"].includes(directionValue)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.find/3", [
          string,
          searchPattern,
          direction,
        ]),
      );
    }

    const stringText = Bitstring.toText(stringBinary);
    const patternText = Bitstring.toText(patternBinary);

    // Empty pattern returns the string as-is
    if (Bitstring.isEmpty(patternBinary)) {
      return Type.isList(string)
        ? Type.charlist(stringText)
        : Type.bitstring(stringText);
    }

    // Find the pattern
    const index =
      directionValue === "trailing"
        ? stringText.lastIndexOf(patternText)
        : stringText.indexOf(patternText);

    if (index === -1) {
      return Type.atom("nomatch");
    }

    // Return the remainder from the match position (inclusive of pattern)
    const result = stringText.slice(index);

    return Type.isList(string) ? Type.charlist(result) : Type.bitstring(result);
  },
  // End find/3
  // Deps: [:unicode.characters_to_binary/1]

  // Start jaro_similarity/2
  "jaro_similarity/2": (string1, string2) => {
    // Like :string.jaro_similarity/2, the comparison is done by grapheme cluster.
    // Each grapheme is reduced to a comparable key (a single codepoint, or the
    // joined codepoints of a multi-codepoint cluster).
    const toGraphemeKeys = (str) =>
      Erlang_String["to_graphemes/1"](str).data.map((grapheme) =>
        Type.isInteger(grapheme)
          ? "c" + grapheme.value.toString()
          : "g" + grapheme.data.map((codepoint) => codepoint.value).join(","),
      );

    const graphemes1 = toGraphemeKeys(string1);
    const graphemes2 = toGraphemeKeys(string2);
    const len1 = graphemes1.length;
    const len2 = graphemes2.length;

    if (len1 === 0 && len2 === 0) {
      return Type.float(1.0);
    }

    if (len1 === 0 || len2 === 0) {
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
        if (!matches2[j] && graphemes1[i] === graphemes2[j]) {
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

        if (graphemes1[i] !== graphemes2[k]) {
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
  // Deps: [:string.to_graphemes/1]

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

  // Start length/1
  "length/1": (string) => {
    const isBinary = Type.isBinary(string);
    const isList = Type.isList(string);

    if (!isBinary && !isList) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [string]),
      );
    }

    // Binary fast path
    if (isBinary) {
      if (Bitstring.isEmpty(string)) return Type.integer(0);

      const text = Bitstring.toText(string);

      if (text !== false) {
        let count = 0;
        for (const _segment of ERTS.graphemeSegmenter.segment(text)) count++;
        return Type.integer(count);
      }
    } else {
      // List fast path

      if (string.data.length === 0) return Type.integer(0);

      let stringBinary;
      let isBinaryObtained = false;

      try {
        stringBinary = Erlang_Unicode["characters_to_binary/1"](string);
        isBinaryObtained = !Type.isTuple(stringBinary);
      } catch {
        // Conversion failed - fall through to gc/1 loop
      }

      if (isBinaryObtained) {
        const text = Bitstring.toText(stringBinary);

        if (text !== false) {
          if (text.length === 0) return Type.integer(0);

          let count = 0;
          for (const _segment of ERTS.graphemeSegmenter.segment(text)) count++;
          return Type.integer(count);
        }
      }
    }

    // Slow path: iterate with gc/1 (handles all error cases correctly)

    let count = 0;
    let current = string;

    while (true) {
      const gcResult = Erlang_Unicode_Util["gc/1"](current);

      if (Type.isList(gcResult) && gcResult.data.length === 0) {
        return Type.integer(count);
      }

      if (Type.isTuple(gcResult)) {
        Interpreter.raiseArgumentError(
          `argument error: ${Interpreter.inspect(gcResult.data[1])}`,
        );
      }

      count++;

      if (Type.isImproperList(gcResult)) {
        current = gcResult.data[gcResult.data.length - 1];
      } else {
        current = Type.list(gcResult.data.slice(1));
      }
    }
  },
  // End length/1
  // Deps: [:unicode.characters_to_binary/1, :unicode_util.gc/1]

  // Start replace/3
  "replace/3": (string, pattern, replacement) => {
    return Erlang_String["replace/4"](
      string,
      pattern,
      replacement,
      Type.atom("leading"),
    );
  },
  // End replace/3
  // Deps: [:string.replace/4]

  // Start replace/4
  "replace/4": (string, pattern, replacement, direction) => {
    let stringBinary;

    // Convert string to binary - re-throw as MatchError (Erlang raises MatchError for invalid string)
    try {
      stringBinary = Erlang_Unicode["characters_to_binary/1"](string);
    } catch {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(string));
    }

    // Convert pattern to binary - let ArgumentError propagate naturally
    const patternBinary = Erlang_Unicode["characters_to_binary/1"](pattern);

    if (!Type.isAtom(direction)) {
      Interpreter.raiseCaseClauseError(direction);
    }

    const stringText = Bitstring.toText(stringBinary);
    const patternText = Bitstring.toText(patternBinary);

    if (Bitstring.isEmpty(patternBinary) || !stringText.includes(patternText)) {
      return Type.list([Type.bitstring(stringText)]);
    }

    let resultList, index;

    switch (direction.value) {
      case "all":
        resultList = stringText.split(patternText).flatMap((elem, idx) => {
          return idx === 0
            ? [Type.bitstring(elem)]
            : [replacement, Type.bitstring(elem)];
        });
        break;

      case "trailing":
        index = stringText.lastIndexOf(patternText);
        resultList = [
          Type.bitstring(stringText.slice(0, index)),
          replacement,
          Type.bitstring(stringText.slice(index + patternText.length)),
        ];
        break;

      case "leading":
        index = stringText.indexOf(patternText);
        resultList = [
          Type.bitstring(stringText.slice(0, index)),
          replacement,
          Type.bitstring(stringText.slice(index + patternText.length)),
        ];
        break;

      default:
        Interpreter.raiseCaseClauseError(direction);
    }

    return Type.list(resultList);
  },
  // End replace/4
  // Deps: [:unicode.characters_to_binary/1]

  // Start split/2
  "split/2": (subject, pattern) => {
    return Erlang_String["split/3"](subject, pattern, Type.atom("leading"));
  },
  // End split/2
  // Deps: [:string.split/3]

  // Start split/3
  "split/3": (subject, pattern, direction) => {
    let subjectBinary;
    try {
      subjectBinary = Erlang_Unicode["characters_to_binary/1"](subject);
    } catch {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(subject));
    }

    if (Type.isTuple(subjectBinary)) {
      Interpreter.raiseMatchError(Interpreter.buildMatchErrorMsg(subject));
    }

    const patternBinary = Erlang_Unicode["characters_to_binary/1"](pattern);

    if (Type.isTuple(patternBinary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    }

    if (!Type.isAtom(direction)) {
      Interpreter.raiseCaseClauseError(direction);
    }

    const directionValue = direction.value;

    if (!["all", "leading", "trailing"].includes(directionValue)) {
      Interpreter.raiseCaseClauseError(direction);
    }

    const subjectText = Bitstring.toText(subjectBinary);
    const patternText = Bitstring.toText(patternBinary);

    const convertResult = (str) =>
      Type.isList(subject) ? Type.charlist(str) : str;

    if (
      Bitstring.isEmpty(patternBinary) ||
      !subjectText.includes(patternText)
    ) {
      return Type.list([convertResult(subjectText)]);
    }

    let parts;

    if (directionValue === "all") {
      parts = subjectText.split(patternText);
    } else {
      const index =
        directionValue === "trailing"
          ? subjectText.lastIndexOf(patternText)
          : subjectText.indexOf(patternText);

      parts = [
        subjectText.slice(0, index),
        subjectText.slice(index + patternText.length),
      ];
    }

    return Type.list(parts.map(convertResult));
  },
  // End split/3
  // Deps: [:unicode.characters_to_binary/1]

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
      const cpResult = Erlang_Unicode_Util["cp/1"](subject);

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
        (codepoint >= 8104 && codepoint <= 8111)
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

  // Start to_graphemes/1
  "to_graphemes/1": (string) => {
    const graphemes = [];
    let current = string;

    while (true) {
      const result = Erlang_Unicode_Util["gc/1"](current);

      // An empty list signals the end of the input.
      if (Type.isList(result) && result.data.length === 0) {
        break;
      }

      // gc/1 returns {:error, rest} for invalid character data.
      if (Type.isTuple(result) && result.data.length === 2) {
        const [tag, rest] = result.data;

        if (Type.isAtom(tag) && tag.value === "error") {
          Interpreter.raiseArgumentError(
            `argument error: ${Interpreter.inspect(rest)}`,
          );
        }
      }

      // gc/1 returns [grapheme_cluster | rest].
      graphemes.push(result.data[0]);

      if (Type.isImproperList(result)) {
        // gc/1 may return a multi-element improper tail, e.g. [grapheme | [rest | tail]];
        // reconstruct it rather than dropping everything past the second element.
        current =
          result.data.length === 2
            ? result.data[1]
            : Type.improperList(result.data.slice(1));

        if (Type.isBitstring(current) && Bitstring.isEmpty(current)) {
          break;
        }
      } else if (result.data.length > 1) {
        current = Type.list(result.data.slice(1));
      } else {
        break;
      }
    }

    return Type.list(graphemes);
  },
  // End to_graphemes/1
  // Deps: [:unicode_util.gc/1]
};

export default Erlang_String;

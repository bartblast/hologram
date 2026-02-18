"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Lists from "./lists.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Unicode = {
  // Start characters_to_binary/1
  "characters_to_binary/1": (input) => {
    const encoding = Type.atom("utf8");
    return Erlang_Unicode["characters_to_binary/3"](input, encoding, encoding);
  },
  // End characters_to_binary/1
  // Deps: [:unicode.characters_to_binary/3]

  // Start characters_to_binary/3
  "characters_to_binary/3": (input, inputEncoding, outputEncoding) => {
    // TODO: implement inputEncoding and outputEncoding arguments validation

    // TODO: implement other encodings for inputEncoding param
    if (!Interpreter.isStrictlyEqual(inputEncoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    // TODO: implement other encodings for outputEncoding param
    if (!Interpreter.isStrictlyEqual(outputEncoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    if (Type.isBinary(input)) {
      return input;
    }

    if (!Type.isList(input)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    }

    const flatInput = Erlang_Lists["flatten/1"](input);
    const chunks = [];

    for (let i = 0; i < flatInput.data.length; ++i) {
      const elem = flatInput.data[i];

      if (Type.isBinary(elem)) {
        chunks.push(elem);
      } else if (Type.isInteger(elem)) {
        if (Bitstring.validateCodePoint(elem.value)) {
          const segment = Type.bitstringSegment(elem, {type: "utf8"});
          chunks.push(Bitstring.fromSegments([segment]));
        } else {
          const remainingElems = flatInput.data.slice(i);

          return Type.tuple([
            Type.atom("error"),
            Bitstring.concat(chunks),
            Type.list(remainingElems),
          ]);
        }
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    }

    return Bitstring.concat(chunks);
  },
  // End characters_to_binary/3
  // Deps: [:lists.flatten/1]

  // Start characters_to_list/1
  "characters_to_list/1": (data) => {
    // Helpers

    // Converts a binary to a list of codepoints.
    const convertBinaryToCodepoints = (binary, preDecodedText = null) => {
      const text =
        preDecodedText !== null ? preDecodedText : Bitstring.toText(binary);

      return Array.from(text).map((char) => Type.integer(char.codePointAt(0)));
    };

    // Converts a single codepoint integer to a UTF-8 encoded binary.
    const convertCodepointToBinary = (codepoint) => {
      const segment = Type.bitstringSegment(codepoint, {type: "utf8"});
      return Bitstring.fromSegments([segment]);
    };

    // Creates an error tuple: {:error, converted_so_far, rest}
    const createErrorTuple = (codepoints, rest) => {
      return Type.tuple([Type.atom("error"), Type.list(codepoints), rest]);
    };

    // Creates an incomplete tuple: {:incomplete, converted_so_far, rest}
    const createIncompleteTuple = (codepoints, rest) => {
      return Type.tuple([Type.atom("incomplete"), Type.list(codepoints), rest]);
    };

    // Handles invalid UTF-8 errors from binary input (not wrapped in list).
    // Returns error or incomplete tuple with binary rest.
    const handleInvalidUtf8FromBinary = (invalidBinary) => {
      Bitstring.maybeSetBytesFromText(invalidBinary);
      const bytes = invalidBinary.bytes ?? new Uint8Array(0);
      const validLength = Bitstring.getValidUtf8Length(bytes);

      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));

      const codepoints =
        validLength > 0 ? convertBinaryToCodepoints(validPrefix) : [];

      const isTruncated = Bitstring.isTruncatedUtf8Sequence(bytes, validLength);

      if (isTruncated) {
        return createIncompleteTuple(codepoints, invalidRest);
      }

      return createErrorTuple(codepoints, invalidRest);
    };

    // Handles invalid UTF-8 errors from list input. Returns error or incomplete tuple.
    // For error tuples, the rest is wrapped in a list. For incomplete tuples, it's the binary directly.
    const handleInvalidUtf8FromList = (chunks, invalidBinary) => {
      // Convert all valid chunks to codepoints
      const codepoints =
        chunks.length > 0
          ? convertBinaryToCodepoints(Bitstring.concat(chunks))
          : [];

      // Check if it's a truncated sequence
      Bitstring.maybeSetBytesFromText(invalidBinary);
      const bytes = invalidBinary.bytes ?? new Uint8Array(0);
      const validLength = Bitstring.getValidUtf8Length(bytes);
      const isTruncated = Bitstring.isTruncatedUtf8Sequence(bytes, validLength);

      if (isTruncated) {
        // Incomplete: rest is the binary directly (not wrapped in list)
        return createIncompleteTuple(codepoints, invalidBinary);
      }

      // Error: wrap the original invalid binary in a list, matching Erlang behavior
      const restList = Type.list([invalidBinary]);

      return createErrorTuple(codepoints, restList);
    };

    // Handles invalid code points from list input. Returns error tuple.
    // The invalid code point and any remaining data is wrapped in a list.
    const handleInvalidCodepoint = (
      chunks,
      invalidCodepoint,
      remainingElems,
    ) => {
      const codepoints =
        chunks.length > 0
          ? convertBinaryToCodepoints(Bitstring.concat(chunks))
          : [];

      // Build the rest list with invalid code point and remaining elements
      const restElems = [invalidCodepoint, ...remainingElems];
      const restList = Type.list(restElems);

      return createErrorTuple(codepoints, restList);
    };

    // Processes a single list element, validating and accumulating it.
    // Returns { type, data } object: type is 'valid', 'utf8error', 'codepointerror', or 'invalid'.
    const processElement = (elem, chunks, remainingElems) => {
      // Guard: reject invalid types
      if (!Type.isBinary(elem) && !Type.isInteger(elem)) {
        return {type: "invalid"};
      }

      // Process binary elements
      if (Type.isBinary(elem)) {
        const text = Bitstring.toText(elem);

        return text === false
          ? {type: "utf8error", data: handleInvalidUtf8FromList(chunks, elem)}
          : {type: "valid", data: elem};
      }

      // Process integer elements (guaranteed integer at this point)
      const isValidCodepoint = Bitstring.validateCodePoint(elem.value);
      if (!isValidCodepoint) {
        return {
          type: "codepointerror",
          data: handleInvalidCodepoint(chunks, elem, remainingElems),
        };
      }

      return {type: "valid", data: convertCodepointToBinary(elem)};
    };

    const raiseInvalidChardataError = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    };

    // Main logic

    // Guard: reject non-list, non-binary input early
    const isBinary = Type.isBinary(data);
    const isList = Type.isList(data);

    if (!isBinary && !isList) {
      raiseInvalidChardataError();
    }

    // Fast path for binary input
    if (isBinary) {
      const text = Bitstring.toText(data);

      if (text === false) {
        return handleInvalidUtf8FromBinary(data);
      }

      const codepoints = convertBinaryToCodepoints(data, text);

      return Type.list(codepoints);
    }

    // List path (guaranteed to be list at this point)
    const flatData = Erlang_Lists["flatten/1"](data).data;
    const chunks = [];

    // Process elements: concatenate all valid data first, then convert to codepoints.
    for (let i = 0; i < flatData.length; ++i) {
      const remainingElems = flatData.slice(i + 1);
      const result = processElement(flatData[i], chunks, remainingElems);

      if (result.type === "utf8error" || result.type === "codepointerror") {
        return result.data;
      }

      if (result.type === "invalid") {
        raiseInvalidChardataError();
      }

      // result.type === "valid" - accumulate
      chunks.push(result.data);
    }

    // All elements valid - concatenate and convert to codepoints
    if (chunks.length === 0) {
      return Type.list([]);
    }

    const binary = Bitstring.concat(chunks);
    const codepoints = convertBinaryToCodepoints(binary);

    return Type.list(codepoints);
  },
  // End characters_to_list/1
  // Deps: [:lists.flatten/1]

  // Start characters_to_nfc_binary/1
  "characters_to_nfc_binary/1": (data) => {
    // Helpers

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0])) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);

      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize("NFC"));

      if (Type.isList(rest)) {
        validateListRest(rest);

        // rest.data[0] is the binary with invalid UTF-8
        return Type.tuple([tag, normalizedPrefix, rest.data[0]]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const validLength = Bitstring.getValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);
      const normalizedPrefix = Type.bitstring(validText.normalize("NFC"));

      return Type.tuple([Type.atom("error"), normalizedPrefix, invalidRest]);
    };

    // Main logic

    const utf8 = Type.atom("utf8");

    const converted = Erlang_Unicode["characters_to_binary/3"](
      data,
      utf8,
      utf8,
    );

    // characters_to_binary/3 returns either a binary (success) or error tuple
    if (Type.isTuple(converted)) {
      return handleConversionError(
        converted.data[0],
        converted.data[1],
        converted.data[2],
      );
    }

    // Valid binary - check for UTF-8 validity then normalize
    const text = Bitstring.toText(converted);

    if (text === false) {
      const bytes = converted.bytes ?? new Uint8Array(0);
      return handleInvalidUtf8(bytes);
    }

    const normalized = text.normalize("NFC");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfc_binary/1
  // Deps: [:unicode.characters_to_binary/3]

  // Start characters_to_nfc_list/1
  "characters_to_nfc_list/1": (chardata) => {
    // Helpers

    // Converts a binary to NFC-normalized list of codepoints.
    // Uses JavaScript's String.normalize('NFC') for canonical composition.
    // Pass preDecodedText for performance - avoids redundant UTF-8 decoding.
    const convertBinaryToNormalizedCodepoints = (
      binary,
      preDecodedText = null,
    ) => {
      const text =
        preDecodedText !== null ? preDecodedText : Bitstring.toText(binary);

      const normalized = text.normalize("NFC");

      return Array.from(normalized).map((char) =>
        Type.integer(char.codePointAt(0)),
      );
    };

    // Converts a single codepoint integer to a UTF-8 encoded binary.
    const convertCodepointToBinary = (codepoint) => {
      const segment = Type.bitstringSegment(codepoint, {type: "utf8"});
      return Bitstring.fromSegments([segment]);
    };

    // Creates an error tuple: {:error, normalized_so_far, rest}
    const createErrorTuple = (normalizedCodepoints, rest) => {
      return Type.tuple([
        Type.atom("error"),
        Type.list(normalizedCodepoints),
        rest,
      ]);
    };

    // Handles invalid UTF-8 errors. Always returns error tuple (invalid UTF-8
    // in binaries returns tuples, not exceptions), even if no valid data exists.
    const handleInvalidUtf8 = (chunks, invalidBinary) => {
      // Early return for no valid prefix
      if (chunks.length === 0) {
        return createErrorTuple([], invalidBinary);
      }

      // Normalize valid prefix and return error tuple
      const validBinary = Bitstring.concat(chunks);
      const codepoints = convertBinaryToNormalizedCodepoints(validBinary);

      return createErrorTuple(codepoints, invalidBinary);
    };

    // Processes a single list element, validating and accumulating it.
    // Returns { type, data } object: type is 'valid', 'error', or 'invalid'.
    const processElement = (elem, chunks) => {
      // Guard: reject invalid types
      if (!Type.isBinary(elem) && !Type.isInteger(elem)) {
        return {type: "invalid"};
      }

      // Process binary elements (no nested ifs - use ternary for early exit)
      if (Type.isBinary(elem)) {
        const text = Bitstring.toText(elem);

        return text === false
          ? {type: "error", data: handleInvalidUtf8(chunks, elem)}
          : {type: "valid", data: elem};
      }

      // Process integer elements (guaranteed integer at this point)
      const isValidCodepoint = Bitstring.validateCodePoint(elem.value);
      if (!isValidCodepoint) {
        raiseInvalidChardataError();
      }

      return {type: "valid", data: convertCodepointToBinary(elem)};
    };

    const raiseInvalidChardataError = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    };

    // Main logic

    // Guard: reject non-list, non-binary input early
    const isBinary = Type.isBinary(chardata);
    const isList = Type.isList(chardata);

    if (!isBinary && !isList) {
      raiseInvalidChardataError();
    }

    // Fast path for binary input
    if (isBinary) {
      const result = Erlang_Unicode["characters_to_nfc_binary/1"](chardata);

      if (Type.isTuple(result)) {
        const prefixBin = result.data[1];
        const rest = result.data[2];
        const prefixText = Bitstring.toText(prefixBin);

        const prefixCodepoints =
          prefixText === false
            ? []
            : convertBinaryToNormalizedCodepoints(prefixBin, prefixText);

        return createErrorTuple(prefixCodepoints, rest);
      }

      const codepoints = convertBinaryToNormalizedCodepoints(result);

      return Type.list(codepoints);
    }

    // List path (guaranteed to be list at this point)
    const flatData = Erlang_Lists["flatten/1"](chardata).data;
    const chunks = [];

    // Process elements: concatenate all valid data first (combining characters
    // may span multiple elements), then normalize. O(n) single pass.
    for (let i = 0; i < flatData.length; ++i) {
      const result = processElement(flatData[i], chunks);

      if (result.type === "error") {
        return result.data;
      }

      if (result.type === "invalid") {
        raiseInvalidChardataError();
      }

      // result.type === "valid" - accumulate
      chunks.push(result.data);
    }

    // All elements valid - concatenate, normalize, and return
    const binary = Bitstring.concat(chunks);
    const codepoints = convertBinaryToNormalizedCodepoints(binary);

    return Type.list(codepoints);
  },
  // End characters_to_nfc_list/1
  // Deps: [:lists.flatten/1, :unicode.characters_to_nfc_binary/1]

  // Start characters_to_nfd_binary/1
  "characters_to_nfd_binary/1": (data) => {
    // Helpers

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0])) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);

      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize("NFD"));

      if (Type.isList(rest)) {
        validateListRest(rest);

        // rest.data[0] is the binary with invalid UTF-8
        return Type.tuple([tag, normalizedPrefix, rest.data[0]]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const validLength = Bitstring.getValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);

      const normalizedPrefix = Type.bitstring(validText.normalize("NFD"));

      return Type.tuple([Type.atom("error"), normalizedPrefix, invalidRest]);
    };

    // Main logic

    const utf8 = Type.atom("utf8");

    const converted = Erlang_Unicode["characters_to_binary/3"](
      data,
      utf8,
      utf8,
    );

    // characters_to_binary/3 returns either a binary (success) or error tuple
    if (Type.isTuple(converted)) {
      return handleConversionError(
        converted.data[0],
        converted.data[1],
        converted.data[2],
      );
    }

    // Valid binary - check for UTF-8 validity then normalize
    const text = Bitstring.toText(converted);

    if (text === false) {
      const bytes = converted.bytes ?? new Uint8Array(0);
      return handleInvalidUtf8(bytes);
    }

    const normalized = text.normalize("NFD");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfd_binary/1
  // Deps: [:unicode.characters_to_binary/3]

  // Start characters_to_nfkc_binary/1
  "characters_to_nfkc_binary/1": (data) => {
    // Helpers

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0])) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);

      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize("NFKC"));

      if (Type.isList(rest)) {
        validateListRest(rest);

        // rest.data[0] is the binary with invalid UTF-8
        return Type.tuple([tag, normalizedPrefix, rest.data[0]]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const validLength = Bitstring.getValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);
      const normalizedPrefix = Type.bitstring(validText.normalize("NFKC"));

      return Type.tuple([Type.atom("error"), normalizedPrefix, invalidRest]);
    };

    // Main logic

    const utf8 = Type.atom("utf8");

    const converted = Erlang_Unicode["characters_to_binary/3"](
      data,
      utf8,
      utf8,
    );

    // characters_to_binary/3 returns either a binary (success) or error tuple
    if (Type.isTuple(converted)) {
      return handleConversionError(
        converted.data[0],
        converted.data[1],
        converted.data[2],
      );
    }

    const text = Bitstring.toText(converted);

    // Valid binary - check for UTF-8 validity then normalize
    if (text === false) {
      const bytes = converted.bytes ?? new Uint8Array(0);
      return handleInvalidUtf8(bytes);
    }

    const normalized = text.normalize("NFKC");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfkc_binary/1
  // Deps: [:unicode.characters_to_binary/3]

  // Start characters_to_nfkd_binary/1
  "characters_to_nfkd_binary/1": (data) => {
    // Helpers

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0])) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);

      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize("NFKD"));

      if (Type.isList(rest)) {
        validateListRest(rest);

        // rest.data[0] is the binary with invalid UTF-8
        return Type.tuple([tag, normalizedPrefix, rest.data[0]]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const validLength = Bitstring.getValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);
      const normalizedPrefix = Type.bitstring(validText.normalize("NFKD"));

      return Type.tuple([Type.atom("error"), normalizedPrefix, invalidRest]);
    };

    // Main logic

    const utf8 = Type.atom("utf8");

    const converted = Erlang_Unicode["characters_to_binary/3"](
      data,
      utf8,
      utf8,
    );

    // characters_to_binary/3 returns either a binary (success) or error tuple
    if (Type.isTuple(converted)) {
      return handleConversionError(
        converted.data[0],
        converted.data[1],
        converted.data[2],
      );
    }

    // Valid binary - check for UTF-8 validity then normalize
    const text = Bitstring.toText(converted);
    if (text === false) {
      const bytes = converted.bytes ?? new Uint8Array(0);
      return handleInvalidUtf8(bytes);
    }

    const normalized = text.normalize("NFKD");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfkd_binary/1
  // Deps: [:unicode.characters_to_binary/3]
};

export default Erlang_Unicode;

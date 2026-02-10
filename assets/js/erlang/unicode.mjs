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
  // Start _characters_to_normalized_binary/2 (private helper)
  "_characters_to_normalized_binary/2": (data, normalizationForm) => {
    // Helpers

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0]))
        Erlang_Unicode["_raise_invalid_chardata/0"]();

      return rest;
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);
      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize(normalizationForm));

      if (Type.isList(rest)) {
        // validateListRest(rest).data[0], is the binary with invalid UTF-8
        return Type.tuple([
          tag,
          normalizedPrefix,
          validateListRest(rest).data[0],
        ]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const {validLength} = Erlang_Unicode["_find_valid_utf8_prefix/1"](bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);
      const normalizedPrefix = Type.bitstring(
        validText.normalize(normalizationForm),
      );

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

    if (text === false)
      return handleInvalidUtf8(converted.bytes ?? new Uint8Array(0));

    const normalized = text.normalize(normalizationForm);

    return Type.bitstring(normalized);
  },
  // End _characters_to_normalized_binary/2
  // Deps: [:unicode._find_valid_utf8_prefix/1, :unicode._raise_invalid_chardata/0, :unicode.characters_to_binary/3]

  // Start _convert_binary_to_codepoints/3 (private helper)
  "_convert_binary_to_codepoints/3": (
    binary,
    normalizationForm,
    preDecodedText,
  ) => {
    const text =
      preDecodedText !== null ? preDecodedText : Bitstring.toText(binary);

    const normalized =
      normalizationForm === null ? text : text.normalize(normalizationForm);

    return Array.from(normalized).map((char) =>
      Type.integer(char.codePointAt(0)),
    );
  },
  // End _convert_binary_to_codepoints/3
  // Deps: []

  // Start _convert_codepoint_to_binary/1 (private helper)
  "_convert_codepoint_to_binary/1": (codepoint) => {
    const segment = Type.bitstringSegment(codepoint, {type: "utf8"});
    return Bitstring.fromSegments([segment]);
  },
  // End _convert_codepoint_to_binary/1
  // Deps: []

  // Start _find_valid_utf8_prefix/1 (private helper)
  "_find_valid_utf8_prefix/1": (bytes) => {
    // Scans forward once to find the longest valid UTF-8 prefix.
    // Validates UTF-8 by checking byte structure, decoding code points,
    // and rejecting overlong encodings, surrogates, and out-of-range values.
    // Time complexity: O(n) where n is the number of bytes.

    // Determines the expected UTF-8 sequence length from the leader byte.
    // Returns -1 for invalid leader bytes (e.g., 0xC0, 0xC1, 0xF5+).
    const getSequenceLength = (leaderByte) => {
      if ((leaderByte & 0x80) === 0) return 1; // 0xxxxxxx: ASCII
      if (leaderByte === 0xc0 || leaderByte === 0xc1) return -1; // Overlong encoding leaders
      if (leaderByte >= 0xf5) return -1; // Beyond valid UTF-8 range
      if ((leaderByte & 0xe0) === 0xc0) return 2; // 110xxxxx: 2-byte
      if ((leaderByte & 0xf0) === 0xe0) return 3; // 1110xxxx: 3-byte
      if ((leaderByte & 0xf8) === 0xf0) return 4; // 11110xxx: 4-byte
      return -1; // Invalid leader byte
    };

    // Checks if a byte is a valid UTF-8 continuation byte (10xxxxxx).
    const isValidContinuation = (byte) => (byte & 0xc0) === 0x80;

    // Decodes a UTF-8 sequence starting at the given position.
    // Returns the decoded Unicode code point value.
    const decodeCodePoint = (start, length) => {
      if (length === 1) return bytes[start];

      if (length === 2)
        return ((bytes[start] & 0x1f) << 6) | (bytes[start + 1] & 0x3f);

      if (length === 3)
        return (
          ((bytes[start] & 0x0f) << 12) |
          ((bytes[start + 1] & 0x3f) << 6) |
          (bytes[start + 2] & 0x3f)
        );

      // length === 4
      return (
        ((bytes[start] & 0x07) << 18) |
        ((bytes[start + 1] & 0x3f) << 12) |
        ((bytes[start + 2] & 0x3f) << 6) |
        (bytes[start + 3] & 0x3f)
      );
    };

    // Validates that a code point is within UTF-8 rules:
    // - Not an overlong encoding (using more bytes than necessary)
    // - Not a UTF-16 surrogate (U+D800–U+DFFF)
    // - Not above maximum Unicode (U+10FFFF)
    const isValidCodePoint = (codePoint, encodingLength) => {
      // Check for overlong encodings (security issue)
      const minValueForLength = [0, 0, 0x80, 0x800, 0x10000];
      if (codePoint < minValueForLength[encodingLength]) return false;

      // Reject UTF-16 surrogates (U+D800–U+DFFF)
      if (codePoint >= 0xd800 && codePoint <= 0xdfff) return false;

      // Reject code points beyond Unicode range (> U+10FFFF)
      if (codePoint > 0x10ffff) return false;

      return true;
    };

    // Validates a complete UTF-8 sequence at the given position.
    // Checks: sufficient bytes, valid continuations, and valid code point.
    const isValidSequence = (start, length) => {
      // Check if we have enough bytes
      if (start + length > bytes.length) return false;

      // Verify all continuation bytes have correct pattern (10xxxxxx)
      for (let i = 1; i < length; i++) {
        if (!isValidContinuation(bytes[start + i])) return false;
      }

      // Decode and validate the code point value
      const codePoint = decodeCodePoint(start, length);

      return isValidCodePoint(codePoint, length);
    };

    // Checks if there's a truncated (incomplete) sequence at position.
    // Returns true if bytes could be a valid prefix of a UTF-8 sequence.
    const isTruncatedSequence = (start) => {
      if (start < 0 || start >= bytes.length) return false;

      const leaderByte = bytes[start];
      const expectedLength = getSequenceLength(leaderByte);

      if (expectedLength <= 0) return false;

      const availableBytes = bytes.length - start;
      if (availableBytes >= expectedLength) return false;

      // Check all available continuation bytes
      for (let i = 1; i < availableBytes; i++) {
        if (!isValidContinuation(bytes[start + i])) return false;
      }

      return true;
    };

    // Main loop: scan forward, validating each sequence
    let pos = 0;

    while (pos < bytes.length) {
      const seqLength = getSequenceLength(bytes[pos]);
      if (seqLength === -1 || !isValidSequence(pos, seqLength)) break;
      pos += seqLength;
    }

    return {validLength: pos, isTruncated: isTruncatedSequence(pos)};
  },
  // End _find_valid_utf8_prefix/1
  // Deps: []

  // Start _process_chardata_list/3 (private helper)
  "_process_chardata_list/3": (flatData, processElement, onEarlyReturn) => {
    const chunks = [];

    for (let i = 0; i < flatData.length; ++i) {
      const remainingElems = flatData.slice(i + 1);
      const result = processElement(flatData[i], chunks, remainingElems);

      if (result.type === "invalid")
        Erlang_Unicode["_raise_invalid_chardata/0"]();

      const earlyReturn = onEarlyReturn(result);
      if (earlyReturn !== null) return {type: "early", data: earlyReturn};

      chunks.push(result.data);
    }

    return {type: "ok", data: chunks};
  },
  // End _process_chardata_list/3
  // Deps: [:unicode._raise_invalid_chardata/0]

  // Start _raise_invalid_chardata/0 (private helper)
  "_raise_invalid_chardata/0": () => {
    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(
        1,
        "not valid character data (an iodata term)",
      ),
    );
  },
  // End _raise_invalid_chardata/0
  // Deps: []

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

    if (Type.isBinary(input)) return input;

    if (!Type.isList(input)) Erlang_Unicode["_raise_invalid_chardata/0"]();

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
        Erlang_Unicode["_raise_invalid_chardata/0"]();
      }
    }

    return Bitstring.concat(chunks);
  },
  // End characters_to_binary/3
  // Deps: [:lists.flatten/1]

  // Start characters_to_list/1
  "characters_to_list/1": (data) => {
    // Helpers

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
      const {validLength, isTruncated} =
        Erlang_Unicode["_find_valid_utf8_prefix/1"](bytes);

      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));

      const codepoints =
        validLength > 0
          ? Erlang_Unicode["_convert_binary_to_codepoints/3"](
              validPrefix,
              null,
              null,
            )
          : [];

      if (isTruncated) return createIncompleteTuple(codepoints, invalidRest);

      return createErrorTuple(codepoints, invalidRest);
    };

    // Handles invalid UTF-8 errors from list input. Returns error or incomplete tuple.
    // For error tuples, the rest is wrapped in a list. For incomplete tuples, it's the binary directly.
    const handleInvalidUtf8FromList = (chunks, invalidBinary) => {
      // Convert all valid chunks to codepoints
      const codepoints =
        chunks.length > 0
          ? Erlang_Unicode["_convert_binary_to_codepoints/3"](
              Bitstring.concat(chunks),
              null,
              null,
            )
          : [];

      // Check if it's a truncated sequence
      Bitstring.maybeSetBytesFromText(invalidBinary);
      const bytes = invalidBinary.bytes ?? new Uint8Array(0);
      const {isTruncated} = Erlang_Unicode["_find_valid_utf8_prefix/1"](bytes);

      // Incomplete: rest is the binary directly (not wrapped in list)
      if (isTruncated) return createIncompleteTuple(codepoints, invalidBinary);

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
          ? Erlang_Unicode["_convert_binary_to_codepoints/3"](
              Bitstring.concat(chunks),
              null,
              null,
            )
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
      if (!Type.isBinary(elem) && !Type.isInteger(elem))
        return {type: "invalid"};

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

      return {
        type: "valid",
        data: Erlang_Unicode["_convert_codepoint_to_binary/1"](elem),
      };
    };

    // Main logic

    // Guard: reject non-list, non-binary input early
    const isBinary = Type.isBinary(data);
    const isList = Type.isList(data);

    if (!isBinary && !isList) Erlang_Unicode["_raise_invalid_chardata/0"]();

    // Fast path for binary input
    if (isBinary) {
      const text = Bitstring.toText(data);

      if (text === false) return handleInvalidUtf8FromBinary(data);

      const codepoints = Erlang_Unicode["_convert_binary_to_codepoints/3"](
        data,
        null,
        text,
      );

      return Type.list(codepoints);
    }

    // List path (guaranteed to be list at this point)
    const flatData = Erlang_Lists["flatten/1"](data).data;
    const listResult = Erlang_Unicode["_process_chardata_list/3"](
      flatData,
      (elem, chunks, remainingElems) =>
        processElement(elem, chunks, remainingElems),
      (result) => {
        return result.type === "utf8error" || result.type === "codepointerror"
          ? result.data
          : null;
      },
    );

    if (listResult.type === "early") return listResult.data;

    const chunks = listResult.data;

    // All elements valid - concatenate and convert to codepoints
    if (chunks.length === 0) return Type.list([]);

    const binary = Bitstring.concat(chunks);
    const codepoints = Erlang_Unicode["_convert_binary_to_codepoints/3"](
      binary,
      null,
      null,
    );

    return Type.list(codepoints);
  },
  // End characters_to_list/1
  // Deps: [:unicode._convert_binary_to_codepoints/3, :unicode._convert_codepoint_to_binary/1, :unicode._find_valid_utf8_prefix/1, :unicode._process_chardata_list/3, :unicode._raise_invalid_chardata/0, :lists.flatten/1]

  // Start characters_to_nfc_binary/1
  "characters_to_nfc_binary/1": (data) => {
    return Erlang_Unicode["_characters_to_normalized_binary/2"](data, "NFC");
  },
  // End characters_to_nfc_binary/1
  // Deps: [:unicode._characters_to_normalized_binary/2]

  // Start characters_to_nfc_list/1
  "characters_to_nfc_list/1": (chardata) => {
    // Helpers

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
      if (chunks.length === 0) return createErrorTuple([], invalidBinary);

      // Normalize valid prefix and return error tuple
      const validBinary = Bitstring.concat(chunks);
      const codepoints = Erlang_Unicode["_convert_binary_to_codepoints/3"](
        validBinary,
        "NFC",
        null,
      );

      return createErrorTuple(codepoints, invalidBinary);
    };

    // Processes a single list element, validating and accumulating it.
    // Returns { type, data } object: type is 'valid', 'error', or 'invalid'.
    const processElement = (elem, chunks) => {
      // Guard: reject invalid types
      if (!Type.isBinary(elem) && !Type.isInteger(elem))
        return {type: "invalid"};

      // Process binary elements (no nested ifs - use ternary for early exit)
      if (Type.isBinary(elem)) {
        const text = Bitstring.toText(elem);

        return text === false
          ? {type: "error", data: handleInvalidUtf8(chunks, elem)}
          : {type: "valid", data: elem};
      }

      // Process integer elements (guaranteed integer at this point)
      const isValidCodepoint = Bitstring.validateCodePoint(elem.value);
      if (!isValidCodepoint) Erlang_Unicode["_raise_invalid_chardata/0"]();

      return {
        type: "valid",
        data: Erlang_Unicode["_convert_codepoint_to_binary/1"](elem),
      };
    };

    // Main logic

    // Guard: reject non-list, non-binary input early
    const isBinary = Type.isBinary(chardata);
    const isList = Type.isList(chardata);

    if (!isBinary && !isList) Erlang_Unicode["_raise_invalid_chardata/0"]();

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
            : Erlang_Unicode["_convert_binary_to_codepoints/3"](
                prefixBin,
                "NFC",
                prefixText,
              );

        return createErrorTuple(prefixCodepoints, rest);
      }

      const codepoints = Erlang_Unicode["_convert_binary_to_codepoints/3"](
        result,
        "NFC",
        null,
      );

      return Type.list(codepoints);
    }

    // List path (guaranteed to be list at this point)
    const flatData = Erlang_Lists["flatten/1"](chardata).data;
    const listResult = Erlang_Unicode["_process_chardata_list/3"](
      flatData,
      (elem, chunks) => processElement(elem, chunks),
      (result) => {
        return result.type === "error" ? result.data : null;
      },
    );

    if (listResult.type === "early") return listResult.data;

    const chunks = listResult.data;

    // All elements valid - concatenate, normalize, and return
    const binary = Bitstring.concat(chunks);
    const codepoints = Erlang_Unicode["_convert_binary_to_codepoints/3"](
      binary,
      "NFC",
      null,
    );

    return Type.list(codepoints);
  },
  // End characters_to_nfc_list/1
  // Deps: [:unicode._convert_binary_to_codepoints/3, :unicode._convert_codepoint_to_binary/1, :unicode._process_chardata_list/3, :unicode._raise_invalid_chardata/0, :unicode.characters_to_nfc_binary/1, :lists.flatten/1]

  // Start characters_to_nfd_binary/1
  "characters_to_nfd_binary/1": (data) => {
    return Erlang_Unicode["_characters_to_normalized_binary/2"](data, "NFD");
  },
  // End characters_to_nfd_binary/1
  // Deps: [:unicode._characters_to_normalized_binary/2]

  // Start characters_to_nfkc_binary/1
  "characters_to_nfkc_binary/1": (data) => {
    return Erlang_Unicode["_characters_to_normalized_binary/2"](data, "NFKC");
  },
  // End characters_to_nfkc_binary/1
  // Deps: [:unicode._characters_to_normalized_binary/2]

  // Start characters_to_nfkd_binary/1
  "characters_to_nfkd_binary/1": (data) => {
    return Erlang_Unicode["_characters_to_normalized_binary/2"](data, "NFKD");
  },
  // End characters_to_nfkd_binary/1
  // Deps: [:unicode._characters_to_normalized_binary/2]
};

export default Erlang_Unicode;

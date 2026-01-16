"use strict";

import Bitstring from "../bitstring.mjs";
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

  // TODO: finish porting (at the moment only UTF8 binary input is accepted)
  // Start characters_to_list/1
  "characters_to_list/1": (data) => {
    let isValidArg = true;

    if (Type.isList(data)) {
      isValidArg = data.data.every((item) => Bitstring.isText(item));
    } else {
      isValidArg = Bitstring.isText(data);
    }

    if (!isValidArg) {
      throw new HologramInterpreterError(
        "Function :unicode.characters_to_list/1 is not yet fully ported and at the moment accepts only UTF8 binary input.\n" +
          `The following input was received: ${Interpreter.inspect(data)}\n` +
          "See what to do here: https://www.hologram.page/TODO",
      );
    }

    let bitstring;

    if (Type.isList(data)) {
      bitstring = Bitstring.concat(data.data);
    } else {
      bitstring = data;
    }

    return Bitstring.toCodepoints(bitstring);
  },
  // End characters_to_list/1
  // Deps: []

  // Start characters_to_nfc_binary/1
  "characters_to_nfc_binary/1": (data) => {
    // Helpers

    // Scans forward once to find the longest valid UTF-8 prefix.
    // Validates UTF-8 by checking byte structure, decoding code points,
    // and rejecting overlong encodings, surrogates, and out-of-range values.
    // Time complexity: O(n) where n is the number of bytes.
    const findValidUtf8Length = (bytes) => {
      // Determines the expected UTF-8 sequence length from the leader byte.
      // Returns -1 for invalid leader bytes (e.g., 0xC0, 0xC1, 0xF5+).
      const getSequenceLength = (leaderByte) => {
        if ((leaderByte & 0x80) === 0) return 1; // 0xxxxxxx: ASCII
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
        if (length === 1) {
          return bytes[start];
        }

        if (length === 2) {
          return ((bytes[start] & 0x1f) << 6) | (bytes[start + 1] & 0x3f);
        }

        if (length === 3) {
          return (
            ((bytes[start] & 0x0f) << 12) |
            ((bytes[start + 1] & 0x3f) << 6) |
            (bytes[start + 2] & 0x3f)
          );
        }

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

      // Main loop: scan forward, validating each sequence
      let pos = 0;

      while (pos < bytes.length) {
        const seqLength = getSequenceLength(bytes[pos]);
        if (seqLength === -1 || !isValidSequence(pos, seqLength)) break;
        pos += seqLength;
      }

      return pos;
    };

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
      const validLength = findValidUtf8Length(bytes);
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

  // Start characters_to_nfd_binary/1
  "characters_to_nfd_binary/1": (data) => {
    // Helpers

    // Scans forward once to find the longest valid UTF-8 prefix.
    // Validates UTF-8 by checking byte structure, decoding code points,
    // and rejecting overlong encodings, surrogates, and out-of-range values.
    // Time complexity: O(n) where n is the number of bytes.
    const findValidUtf8Length = (bytes) => {
      // Determines the expected UTF-8 sequence length from the leader byte.
      // Returns -1 for invalid leader bytes (e.g., 0xC0, 0xC1, 0xF5+).
      const getSequenceLength = (leaderByte) => {
        if ((leaderByte & 0x80) === 0) return 1; // 0xxxxxxx: ASCII
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
        if (length === 1) {
          return bytes[start];
        }

        if (length === 2) {
          return ((bytes[start] & 0x1f) << 6) | (bytes[start + 1] & 0x3f);
        }

        if (length === 3) {
          return (
            ((bytes[start] & 0x0f) << 12) |
            ((bytes[start + 1] & 0x3f) << 6) |
            (bytes[start + 2] & 0x3f)
          );
        }
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

      // Main loop: scan forward, validating each sequence
      let pos = 0;
      while (pos < bytes.length) {
        const seqLength = getSequenceLength(bytes[pos]);
        if (seqLength === -1 || !isValidSequence(pos, seqLength)) break;
        pos += seqLength;
      }

      return pos;
    };

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
      const validLength = findValidUtf8Length(bytes);
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

    // Scans forward once to find the longest valid UTF-8 prefix.
    // Validates UTF-8 by checking byte structure, decoding code points,
    // and rejecting overlong encodings, surrogates, and out-of-range values.
    // Time complexity: O(n) where n is the number of bytes.
    const findValidUtf8Length = (bytes) => {
      // Determines the expected UTF-8 sequence length from the leader byte.
      // Returns -1 for invalid leader bytes (e.g., 0xC0, 0xC1, 0xF5+).
      const getSequenceLength = (leaderByte) => {
        if ((leaderByte & 0x80) === 0) return 1; // 0xxxxxxx: ASCII
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
        if (length === 1) {
          return bytes[start];
        }
        if (length === 2) {
          return ((bytes[start] & 0x1f) << 6) | (bytes[start + 1] & 0x3f);
        }
        if (length === 3) {
          return (
            ((bytes[start] & 0x0f) << 12) |
            ((bytes[start + 1] & 0x3f) << 6) |
            (bytes[start + 2] & 0x3f)
          );
        }
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
        // Uses functional approach: creates array of indices, tests each with .every()
        const allContinuationsValid = Array.from(
          {length: length - 1},
          (_, i) => i + 1,
        ).every((offset) => isValidContinuation(bytes[start + offset]));

        if (!allContinuationsValid) return false;

        // Decode and validate the code point value
        const codePoint = decodeCodePoint(start, length);
        return isValidCodePoint(codePoint, length);
      };

      // Main loop: scan forward, validating each sequence
      let pos = 0;
      while (pos < bytes.length) {
        const seqLength = getSequenceLength(bytes[pos]);
        if (seqLength === -1 || !isValidSequence(pos, seqLength)) break;
        pos += seqLength;
      }

      return pos;
    };

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
      const validLength = findValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);

      // Guard against validText being false (if validPrefix is somehow invalid UTF-8)
      const normalizedPrefix =
        validText === false
          ? Type.bitstring("")
          : Type.bitstring(validText.normalize("NFKC"));

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
    if (text === false) return handleInvalidUtf8(converted.bytes);

    const normalized = text.normalize("NFKC");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfkc_binary/1
  // Deps: [:unicode.characters_to_binary/3]
};

export default Erlang_Unicode;

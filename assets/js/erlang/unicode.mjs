"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Lists from "./lists.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Unicode = {
  // Start _build_error_tuple (private helper)
  // Builds error tuple: {:error, converted_so_far, rest}
  _build_error_tuple: (binary, rest) =>
    Type.tuple([Type.atom("error"), binary, rest]),
  // End _build_error_tuple
  // Deps: []

  // Start _build_incomplete_tuple (private helper)
  // Builds incomplete tuple: {:incomplete, converted_so_far, rest}
  _build_incomplete_tuple: (binary, rest) =>
    Type.tuple([Type.atom("incomplete"), binary, rest]),
  // End _build_incomplete_tuple
  // Deps: []

  // Start _parse_utf16_binary/2 (private helper)
  // Parses UTF-16 binary to UTF-8 binaries, handling surrogate pairs and endianness
  "_parse_utf16_binary/2": (binary, inEncoding) => {
    // Helper: Read 16-bit unit respecting endianness
    const readUnit16 = (bytes, offset, endian) => {
      const byte1 = bytes[offset];
      const byte2 = bytes[offset + 1];

      return endian === "little" ? (byte2 << 8) | byte1 : (byte1 << 8) | byte2;
    };

    // Helper: Check if value is high surrogate (U+D800–U+DBFF)
    const isHighSurrogate = (unit) => unit >= 0xd800 && unit <= 0xdbff;

    // Helper: Check if value is low surrogate (U+DC00–U+DFFF)
    const isLowSurrogate = (unit) => unit >= 0xdc00 && unit <= 0xdfff;

    // Helper: Combine surrogate pair into codepoint
    const combineSurrogates = (high, low) => {
      return 0x10000 + (((high & 0x3ff) << 10) | (low & 0x3ff));
    };

    // Helper: Create rest bitstring from current position
    const makeRest = (bytes, offset) =>
      Bitstring.fromBytes(bytes.slice(offset));

    // Helper: Process surrogate pair starting at offset
    // Returns: {type: "ok", binary, offsetDelta} | {type: "incomplete"} | {type: "error"}
    const processSurrogatePair = (bytes, offset, highUnit, endian) => {
      // Check if we have enough bytes for low surrogate
      if (offset + 3 >= bytes.length) {
        return {type: "incomplete"};
      }

      // Read and validate low surrogate
      const lowUnit = readUnit16(bytes, offset + 2, endian);
      if (!isLowSurrogate(lowUnit)) {
        return {type: "error"};
      }

      // Combine surrogates and convert to binary
      const codepoint = Type.integer(combineSurrogates(highUnit, lowUnit));
      const binary =
        Erlang_Unicode["_convert_codepoint_to_binary/1"](codepoint);

      return {type: "ok", binary, offsetDelta: 2};
    };

    // Main logic

    const binaries = [];

    const endian = Type.isTuple(inEncoding) ? inEncoding.data[1]?.value : "big";

    const bytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](binary);

    const remainder = bytes.length % 2;
    const lastCompleteIndex = bytes.length - remainder;

    // Parse UTF-16 code units, handling surrogate pairs
    for (let i = 0; i < lastCompleteIndex; i += 2) {
      const unit = readUnit16(bytes, i, endian);

      if (isHighSurrogate(unit)) {
        const result = processSurrogatePair(bytes, i, unit, endian);

        if (result.type === "incomplete")
          return {
            type: "incomplete",
            data: binaries,
            rest: makeRest(bytes, i),
          };

        if (result.type === "error")
          return {type: "error", data: binaries, rest: makeRest(bytes, i)};

        binaries.push(result.binary);

        i += result.offsetDelta; // Skip the low surrogate pair
      } else if (isLowSurrogate(unit)) {
        // Low surrogate without preceding high surrogate
        return {type: "error", data: binaries, rest: makeRest(bytes, i)};
      } else {
        // Regular BMP codepoint
        const codepoint = Type.integer(unit);
        binaries.push(
          Erlang_Unicode["_convert_codepoint_to_binary/1"](codepoint),
        );
      }
    }

    if (remainder > 0)
      return {
        type: "incomplete",
        data: binaries,
        rest: makeRest(bytes, lastCompleteIndex),
      };

    return {type: "ok", data: binaries};
  },
  // End _parse_utf16_binary/2
  // Deps: [:unicode._convert_codepoint_to_binary/1, :unicode._ensure_bytes_from_binary/1]

  // Start _parse_utf32_binary/2 (private helper)
  // Parses UTF-32 binary to UTF-8 binaries, handling endianness and validation
  "_parse_utf32_binary/2": (binary, inEncoding) => {
    // Helper: Read 32-bit codepoint respecting endianness
    const readCodepoint32 = (bytes, offset, endian) => {
      if (endian === "little") {
        // Little-endian: least significant byte first
        return (
          ((bytes[offset + 3] << 24) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 1] << 8) |
            bytes[offset]) >>>
          0
        ); // Force unsigned 32-bit
      } else {
        // Big-endian: most significant byte first
        return (
          ((bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3]) >>>
          0
        ); // Force unsigned 32-bit
      }
    };

    // Helper: Check if codepoint is valid Unicode
    const isValidCodepoint = (cp) => {
      // Must be non-negative and within Unicode range
      if (cp < 0 || cp > 0x10ffff) return false;
      // Must not be surrogate (surrogates are invalid in UTF-32)
      if (cp >= 0xd800 && cp <= 0xdfff) return false;

      return true;
    };

    // Helper: Create rest bitstring from current position
    const makeRest = (bytes, offset) =>
      Bitstring.fromBytes(bytes.slice(offset));

    // Main logic

    const endian = Type.isTuple(inEncoding) ? inEncoding.data[1]?.value : "big";

    const bytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](binary);

    const remainder = bytes.length % 4;
    const lastCompleteIndex = bytes.length - remainder;

    const binaries = [];

    for (let i = 0; i < lastCompleteIndex; i += 4) {
      const codepoint = readCodepoint32(bytes, i, endian);

      if (!isValidCodepoint(codepoint))
        return {type: "error", data: binaries, rest: makeRest(bytes, i)};

      const cp = Type.integer(codepoint);
      binaries.push(Erlang_Unicode["_convert_codepoint_to_binary/1"](cp));
    }

    if (remainder > 0)
      return {
        type: "incomplete",
        data: binaries,
        rest: makeRest(bytes, lastCompleteIndex),
      };

    return {type: "ok", data: binaries};
  },
  // End _parse_utf32_binary/2
  // Deps: [:unicode._convert_codepoint_to_binary/1, :unicode._ensure_bytes_from_binary/1]

  // Start _parse_input_encoding_cttb/2 (private helper)
  // Parses input binary from the specified encoding to UTF-8 codepoints.
  // Returns: array of UTF-8 binaries or error info object.
  "_parse_input_encoding_cttb/2": (binary, inEncoding) => {
    const parseUtf8Binary = (binary) => {
      const text = Bitstring.toText(binary);

      return text === false
        ? {type: "utf8error", data: binary}
        : {type: "ok", data: [binary]};
    };

    const parseLatin1Binary = (binary) => {
      const bytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](binary);

      const binaries = Array.from(bytes).map((byte) => {
        const codepoint = Type.integer(byte);
        return Erlang_Unicode["_convert_codepoint_to_binary/1"](codepoint);
      });

      return {type: "ok", data: binaries};
    };

    const isUtf8Encoding = () =>
      inEncoding.value === "utf8" || inEncoding.value === "unicode";
    const isLatin1Encoding = () => inEncoding.value === "latin1";
    const isUtf16Encoding = () =>
      inEncoding.value === "utf16" ||
      (Type.isTuple(inEncoding) && inEncoding.data[0]?.value === "utf16");
    const isUtf32Encoding = () =>
      inEncoding.value === "utf32" ||
      (Type.isTuple(inEncoding) && inEncoding.data[0]?.value === "utf32");

    // UTF-8: return as-is (already in UTF-8)
    if (isUtf8Encoding()) return parseUtf8Binary(binary);

    // Latin1 (ISO-8859-1): each byte is a codepoint (0-255)
    if (isLatin1Encoding()) return parseLatin1Binary(binary);

    // UTF-16: parse 2-byte pairs (with surrogate pair support)
    if (isUtf16Encoding())
      return Erlang_Unicode["_parse_utf16_binary/2"](binary, inEncoding);

    // UTF-32: parse 4-byte quads
    if (isUtf32Encoding())
      return Erlang_Unicode["_parse_utf32_binary/2"](binary, inEncoding);

    return {type: "ok", data: [binary]};
  },
  // End _parse_input_encoding_cttb/2
  // Deps: [:unicode._convert_codepoint_to_binary/1, :unicode._ensure_bytes_from_binary/1, :unicode._parse_utf16_binary/2, :unicode._parse_utf32_binary/2]

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
    // Note: For normalization, incomplete sequences are treated as errors.
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);
      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize(normalizationForm));

      if (Type.isList(rest)) {
        const binary = validateListRest(rest).data[0];
        // Ensure text property is explicitly set to false for invalid UTF-8
        if (Type.isBinary(binary)) {
          const text = Bitstring.toText(binary);
          if (text === false) binary.text = false;
        }

        return Type.tuple([Type.atom("error"), normalizedPrefix, binary]);
      }

      // Keep rest text unset for non-NFC binary input except truncated cases
      if (
        Type.isBinary(rest) &&
        normalizationForm !== "NFC" &&
        tag.value !== "incomplete"
      ) {
        rest.text = null;
      }

      // Convert incomplete to error for normalization functions
      const resultTag = tag.value === "incomplete" ? Type.atom("error") : tag;

      return Type.tuple([resultTag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const {validPrefix, invalidRest} =
        Erlang_Unicode["_split_at_utf8_validity_boundary/1"](bytes);
      const validText = Bitstring.toText(validPrefix);

      // Explicitly ensure text is set to false for invalid UTF-8
      const text = Bitstring.toText(invalidRest);
      if (text === false) invalidRest.text = false;

      if (normalizationForm !== "NFC") invalidRest.text = null;

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
  // Deps: [:unicode._raise_invalid_chardata/0, :unicode._split_at_utf8_validity_boundary/1, :unicode.characters_to_binary/3]

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

  // Start _encode_with_fixed_width/4 (private helper)
  // Common encoding logic for fixed-width encodings (UTF-16, UTF-32)
  // Takes bytesPerCodepoint and an encoding function that writes codepoint to bytes
  "_encode_with_fixed_width/4": (
    binary,
    wasUtf8Input,
    bytesPerCodepoint,
    encodeFn,
  ) => {
    const text = Bitstring.toText(binary);

    // Invalid UTF-8, can't encode
    if (text === false) return {type: "error", data: binary};

    const codepoints = Array.from(text).map((char) => char.codePointAt(0));
    const bytes = new Uint8Array(codepoints.length * bytesPerCodepoint);

    // Encode each codepoint using the provided encoding function
    for (let i = 0; i < codepoints.length; i++) {
      encodeFn(codepoints[i], bytes, i * bytesPerCodepoint);
    }

    const encoded = Bitstring.fromBytes(bytes);

    // Set text only if original input was UTF-8
    const canSetText =
      wasUtf8Input &&
      binary.text !== undefined &&
      binary.text !== null &&
      binary.text !== false;

    if (canSetText) encoded.text = binary.text;

    return {type: "ok", data: encoded};
  },
  // End _encode_with_fixed_width/4
  // Deps: []

  // Start _encode_as_latin1/2 (private helper)
  // Encodes UTF-8 binary to latin1 (ISO-8859-1) - 1 byte per codepoint
  "_encode_as_latin1/2": (binary, wasUtf8Input) => {
    const text = Bitstring.toText(binary);

    // Invalid UTF-8, can't encode to latin1
    if (text === false) return {type: "error", data: binary};

    const codepoints = Array.from(text).map((char) => char.codePointAt(0));

    // Check if any codepoint exceeds latin1 range
    const outOfRange = codepoints.findIndex((cp) => cp > 255);

    if (outOfRange >= 0) {
      // Encode valid prefix and reject the rest
      const validCodepoints = codepoints.slice(0, outOfRange);
      const validText = String.fromCodePoint(...validCodepoints);
      const validBinary = Bitstring.fromBytes(new Uint8Array(validCodepoints));
      validBinary.text = validText.length > 0 ? validText : "";

      // The remaining text starting from first out-of-range codepoint
      const invalidText = text.slice(outOfRange);
      const invalidBinary = Type.bitstring(invalidText);

      return {type: "encoding_error", validBinary, invalidBinary};
    }

    // All codepoints fit in latin1 - encode as bytes
    const bytes = new Uint8Array(codepoints);
    const encoded = Bitstring.fromBytes(bytes);

    // Set text only if original input was UTF-8
    const canSetText =
      wasUtf8Input &&
      binary.text !== undefined &&
      binary.text !== null &&
      binary.text !== false;

    if (canSetText) encoded.text = binary.text;

    return {type: "ok", data: encoded};
  },
  // End _encode_as_latin1/2
  // Deps: []

  // Start _encode_as_utf16_big_endian/2 (private helper)
  // Encodes UTF-8 binary to UTF-16 big-endian, handling surrogate pairs for supplementary characters
  "_encode_as_utf16_big_endian/2": (binary, wasUtf8Input) => {
    const text = Bitstring.toText(binary);

    // Invalid UTF-8, can't encode
    if (text === false) return {type: "error", data: binary};

    const codepoints = Array.from(text).map((char) => char.codePointAt(0));

    // Calculate total bytes needed (BMP: 2 bytes, supplementary: 4 bytes)
    let totalBytes = 0;
    for (const cp of codepoints) {
      totalBytes += cp > 0xffff ? 4 : 2;
    }

    const bytes = new Uint8Array(totalBytes);
    let offset = 0;

    // Encode each codepoint
    for (const cp of codepoints) {
      if (cp > 0xffff) {
        // Supplementary plane: encode as surrogate pair
        const high = 0xd800 + ((cp - 0x10000) >> 10);
        const low = 0xdc00 + ((cp - 0x10000) & 0x3ff);
        // Big-endian: MSB first
        bytes[offset++] = (high >> 8) & 0xff;
        bytes[offset++] = high & 0xff;
        bytes[offset++] = (low >> 8) & 0xff;
        bytes[offset++] = low & 0xff;
      } else {
        // BMP: encode directly
        bytes[offset++] = (cp >> 8) & 0xff;
        bytes[offset++] = cp & 0xff;
      }
    }

    const encoded = Bitstring.fromBytes(bytes);

    // Set text only if original input was UTF-8
    const canSetText =
      wasUtf8Input &&
      binary.text !== undefined &&
      binary.text !== null &&
      binary.text !== false;

    if (canSetText) encoded.text = binary.text;

    return {type: "ok", data: encoded};
  },
  // End _encode_as_utf16_big_endian/2
  // Deps: []

  // Start _encode_as_utf16_little_endian/2 (private helper)
  // Encodes UTF-8 binary to UTF-16 little-endian, handling surrogate pairs for supplementary characters
  "_encode_as_utf16_little_endian/2": (binary, wasUtf8Input) => {
    const text = Bitstring.toText(binary);

    // Invalid UTF-8, can't encode
    if (text === false) return {type: "error", data: binary};

    const codepoints = Array.from(text).map((char) => char.codePointAt(0));

    // Calculate total bytes needed (BMP: 2 bytes, supplementary: 4 bytes)
    let totalBytes = 0;
    for (const cp of codepoints) {
      totalBytes += cp > 0xffff ? 4 : 2;
    }

    const bytes = new Uint8Array(totalBytes);
    let offset = 0;

    // Encode each codepoint
    for (const cp of codepoints) {
      if (cp > 0xffff) {
        // Supplementary plane: encode as surrogate pair
        const high = 0xd800 + ((cp - 0x10000) >> 10);
        const low = 0xdc00 + ((cp - 0x10000) & 0x3ff);
        // Little-endian: LSB first
        bytes[offset++] = high & 0xff;
        bytes[offset++] = (high >> 8) & 0xff;
        bytes[offset++] = low & 0xff;
        bytes[offset++] = (low >> 8) & 0xff;
      } else {
        // BMP: encode directly
        bytes[offset++] = cp & 0xff;
        bytes[offset++] = (cp >> 8) & 0xff;
      }
    }

    const encoded = Bitstring.fromBytes(bytes);

    // Set text only if original input was UTF-8
    const canSetText =
      wasUtf8Input &&
      binary.text !== undefined &&
      binary.text !== null &&
      binary.text !== false;

    if (canSetText) encoded.text = binary.text;

    return {type: "ok", data: encoded};
  },
  // End _encode_as_utf16_little_endian/2
  // Deps: []

  // Start _encode_as_utf32_big_endian/2 (private helper)
  // Encodes UTF-8 binary to UTF-32 big-endian - 4 bytes per codepoint
  "_encode_as_utf32_big_endian/2": (binary, wasUtf8Input) => {
    return Erlang_Unicode["_encode_with_fixed_width/4"](
      binary,
      wasUtf8Input,
      4,
      (codepoint, bytes, offset) => {
        bytes[offset] = (codepoint >> 24) & 0xff;
        bytes[offset + 1] = (codepoint >> 16) & 0xff;
        bytes[offset + 2] = (codepoint >> 8) & 0xff;
        bytes[offset + 3] = codepoint & 0xff;
      },
    );
  },
  // End _encode_as_utf32_big_endian/2
  // Deps: [:unicode._encode_with_fixed_width/4]

  // Start _encode_as_utf32_little_endian/2 (private helper)
  // Encodes UTF-8 binary to UTF-32 little-endian - 4 bytes per codepoint
  "_encode_as_utf32_little_endian/2": (binary, wasUtf8Input) => {
    return Erlang_Unicode["_encode_with_fixed_width/4"](
      binary,
      wasUtf8Input,
      4,
      (codepoint, bytes, offset) => {
        bytes[offset] = codepoint & 0xff;
        bytes[offset + 1] = (codepoint >> 8) & 0xff;
        bytes[offset + 2] = (codepoint >> 16) & 0xff;
        bytes[offset + 3] = (codepoint >> 24) & 0xff;
      },
    );
  },
  // End _encode_as_utf32_little_endian/2
  // Deps: [:unicode._encode_with_fixed_width/4]

  // Start _encode_to_target_encoding_cttb/3 (private helper)
  // Encodes UTF-8 binary to the target encoding.
  // Returns: encoded binary or error info object.
  "_encode_to_target_encoding_cttb/3": (
    utf8Binary,
    outEncoding,
    wasUtf8Input = false,
  ) => {
    // Rule:
    // - If input encoding was UTF-8, preserve input.text through any output encoding
    // - If input encoding was non-UTF-8, never set text on output (unless output is UTF-8)
    // - If output encoding is UTF-8, always set text (UTF-8 is canonical text format)

    const isEncodingOutUtf8 = () =>
      outEncoding.value === "utf8" || outEncoding.value === "unicode";

    const isEncodingOutLatin1 = () => outEncoding.value === "latin1";

    const isEncodingOutUtf16BigEndian = () =>
      (Type.isTuple(outEncoding) &&
        outEncoding.data[0]?.value === "utf16" &&
        outEncoding.data[1]?.value === "big") ||
      (!Type.isTuple(outEncoding) && outEncoding.value === "utf16");

    const isEncodingOutUtf16LittleEndian = () =>
      Type.isTuple(outEncoding) &&
      outEncoding.data[0]?.value === "utf16" &&
      outEncoding.data[1]?.value === "little";

    const isEncodingOutUtf32BigEndian = () =>
      (Type.isTuple(outEncoding) &&
        outEncoding.data[0]?.value === "utf32" &&
        outEncoding.data[1]?.value === "big") ||
      (!Type.isTuple(outEncoding) && outEncoding.value === "utf32");

    const isEncodingOutUtf32LittleEndian = () =>
      Type.isTuple(outEncoding) &&
      outEncoding.data[0]?.value === "utf32" &&
      outEncoding.data[1]?.value === "little";

    // UTF-8: return as-is, always set text (UTF-8 is canonical text encoding)
    if (isEncodingOutUtf8()) {
      const inputText = utf8Binary.text;
      const hasValidInputText =
        inputText !== undefined && inputText !== null && inputText !== false;

      utf8Binary.text = hasValidInputText
        ? inputText
        : Bitstring.toText(utf8Binary);

      return {type: "ok", data: utf8Binary};
    }

    if (isEncodingOutLatin1())
      return Erlang_Unicode["_encode_as_latin1/2"](utf8Binary, wasUtf8Input);

    if (isEncodingOutUtf16BigEndian())
      return Erlang_Unicode["_encode_as_utf16_big_endian/2"](
        utf8Binary,
        wasUtf8Input,
      );

    if (isEncodingOutUtf16LittleEndian())
      return Erlang_Unicode["_encode_as_utf16_little_endian/2"](
        utf8Binary,
        wasUtf8Input,
      );

    if (isEncodingOutUtf32BigEndian())
      return Erlang_Unicode["_encode_as_utf32_big_endian/2"](
        utf8Binary,
        wasUtf8Input,
      );

    if (isEncodingOutUtf32LittleEndian())
      return Erlang_Unicode["_encode_as_utf32_little_endian/2"](
        utf8Binary,
        wasUtf8Input,
      );

    // Unknown encoding: treat as UTF-8 passthrough
    return {type: "ok", data: utf8Binary};
  },
  // End _encode_to_target_encoding_cttb/3
  // Deps: [:unicode._encode_as_latin1/2, :unicode._encode_as_utf16_big_endian/2, :unicode._encode_as_utf16_little_endian/2, :unicode._encode_as_utf32_big_endian/2, :unicode._encode_as_utf32_little_endian/2]

  // Start _ensure_bytes_from_binary/1 (private helper)
  "_ensure_bytes_from_binary/1": (binary) => {
    Bitstring.maybeSetBytesFromText(binary);
    return binary.bytes ?? new Uint8Array(0);
  },
  // End _ensure_bytes_from_binary/1
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

  // Start _handle_binary_input_cttb/3 (private helper)
  // Handles binary input.
  // Parses from input encoding and encodes to target encoding.
  "_handle_binary_input_cttb/3": (binary, inputEncoding, outputEncoding) => {
    const handleUtf8Error = (result) => {
      const binaryWithBytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](
        result.data,
      );

      const {validPrefix, invalidRest, isTruncated, validLength} =
        Erlang_Unicode["_split_at_utf8_validity_boundary/1"](binaryWithBytes);

      Bitstring.maybeSetBytesFromText(invalidRest);
      invalidRest.text = false;

      // Use Type.bitstring for empty prefix if validLength is 0
      const encodedBinary =
        validLength === 0 ? Type.bitstring("") : validPrefix;

      if (isTruncated)
        return Erlang_Unicode["_build_incomplete_tuple"](
          encodedBinary,
          invalidRest,
        );

      return Erlang_Unicode["_build_error_tuple"](encodedBinary, invalidRest);
    };

    const handleIncompleteInput = (
      result,
      encodeToTargetEncoding,
      isUtf8Input,
    ) => {
      const validChunks = result.data;
      const encodedBinary =
        validChunks.length > 0
          ? encodeToTargetEncoding(
              Bitstring.concat(validChunks),
              outputEncoding,
              isUtf8Input,
            ).data
          : Type.bitstring("");

      Bitstring.maybeSetBytesFromText(result.rest);
      result.rest.text = false;

      return Erlang_Unicode["_build_incomplete_tuple"](
        encodedBinary,
        result.rest,
      );
    };

    const handleOtherUtfError = (
      result,
      encodeToTargetEncoding,
      isUtf8Input,
    ) => {
      const validChunks = result.data;
      const encodedBinary =
        validChunks.length > 0
          ? encodeToTargetEncoding(
              Bitstring.concat(validChunks),
              outputEncoding,
              isUtf8Input,
            ).data
          : Type.bitstring("");

      Bitstring.maybeSetBytesFromText(result.rest);
      result.rest.text = false;

      return Erlang_Unicode["_build_error_tuple"](encodedBinary, result.rest);
    };

    // Determine if input encoding is UTF-8 (for text preservation)
    const isUtf8Input =
      inputEncoding.value === "utf8" || inputEncoding.value === "unicode";

    const encodeToTargetEncoding = (utf8Binary, outEncoding, wasUtf8Input) =>
      Erlang_Unicode["_encode_to_target_encoding_cttb/3"](
        utf8Binary,
        outEncoding,
        wasUtf8Input,
      );

    const parseResult = Erlang_Unicode["_parse_input_encoding_cttb/2"](
      binary,
      inputEncoding,
    );

    if (parseResult.type === "utf8error") return handleUtf8Error(parseResult);

    // Handle incomplete UTF-16/UTF-32 sequences
    if (parseResult.type === "incomplete")
      return handleIncompleteInput(
        parseResult,
        encodeToTargetEncoding,
        isUtf8Input,
      );

    // Handle invalid UTF-16/UTF-32 sequences
    if (parseResult.type === "error")
      return handleOtherUtfError(
        parseResult,
        encodeToTargetEncoding,
        isUtf8Input,
      );

    // At this point, we have a valid UTF-8 binary representation of the input text
    // (or the original binary if it was non-UTF-8).

    // Concatenate parsed input and encode to target
    const utf8Binary =
      parseResult.data.length > 1
        ? Bitstring.concat(parseResult.data)
        : parseResult.data[0];

    const encResult = encodeToTargetEncoding(
      utf8Binary,
      outputEncoding,
      isUtf8Input,
    );

    // If encoding to target failed (e.g., due to latin1 out-of-range), return
    // error tuple with what was successfully converted
    if (encResult.type === "encoding_error")
      return Erlang_Unicode["_build_error_tuple"](
        encResult.validBinary,
        encResult.invalidBinary,
      );

    return encResult.data;
  },
  // End _handle_binary_input_cttb/3
  // Deps: [:unicode._build_error_tuple/2, :unicode._build_incomplete_tuple/2, :unicode._encode_to_target_encoding_cttb/3, :unicode._ensure_bytes_from_binary/1, :unicode._parse_input_encoding_cttb/2, :unicode._split_at_utf8_validity_boundary/1]

  // Start _handle_integer_input_cttb/3 (private helper)
  // Handles integer (codepoint) input.
  // Validates and encodes a single codepoint to target encoding.
  "_handle_integer_input_cttb/3": (
    codepoint,
    _inputEncoding,
    outputEncoding,
  ) => {
    const isSurrogateCodepoint =
      codepoint.value >= 0xd800 && codepoint.value <= 0xdfff;
    const isValidCodepoint = Bitstring.validateCodePoint(codepoint.value);

    if (!isValidCodepoint || isSurrogateCodepoint)
      Erlang_Unicode["_raise_invalid_chardata/0"]();

    const isLatin1WithInvalidCodepoint =
      outputEncoding.value === "latin1" && codepoint.value > 255;

    if (isLatin1WithInvalidCodepoint)
      Erlang_Unicode["_raise_invalid_chardata/0"]();

    // Convert codepoint to UTF-8 binary first
    const binary = Erlang_Unicode["_convert_codepoint_to_binary/1"](codepoint);

    // Integer input is not UTF-8 text input, so wasUtf8Input = false
    const encResult = Erlang_Unicode["_encode_to_target_encoding_cttb/3"](
      binary,
      outputEncoding,
      false,
    );

    return encResult.data;
  },
  // End _handle_integer_input_cttb/3
  // Deps: [:unicode._convert_codepoint_to_binary/1, :unicode._encode_to_target_encoding_cttb/3, :unicode._raise_invalid_chardata/0]

  // Start _handle_list_input_cttb/2 (private helper)
  // Handles list input.
  // Processes list recursively without flattening, for O(n) performance.
  "_handle_list_input_cttb/2": (list, outputEncoding) => {
    const encodeToTargetEncoding = (utf8Binary, outEncoding, wasUtf8Input) =>
      Erlang_Unicode["_encode_to_target_encoding_cttb/3"](
        utf8Binary,
        outEncoding,
        wasUtf8Input,
      );

    const processElement = (elem, outputEnc) =>
      Erlang_Unicode["_process_element_cttb/2"](elem, outputEnc);

    const handleUtf8Error = (validChunks, invalidBinary, outputEnc) =>
      Erlang_Unicode["_handle_utf8_error_cttb/3"](
        validChunks,
        invalidBinary,
        outputEnc,
      );

    const handleEncodingError = (result) => {
      const encodeValidChunks = (validChunks, validData, outputEncoding) => {
        // Concatenate all valid chunks and the validData from the encoding error
        const allValidBinaries = validData
          ? [...validChunks, validData]
          : validChunks;

        if (allValidBinaries.length === 0) {
          const empty = Bitstring.fromBytes(new Uint8Array(0));
          empty.text = "";
          return empty;
        }

        return encodeToTargetEncoding(
          Bitstring.concat(allValidBinaries),
          outputEncoding,
        ).data;
      };

      // If encoding error occurs, we return an error tuple with the valid prefix
      // encoded to the target encoding, and the invalid chunk (which caused the
      // encoding error) as the first element of the rest list, followed by any
      // remaining unprocessed elements.
      const encodedPrefix = encodeValidChunks(
        result.validChunks,
        result.validData,
        outputEncoding,
      );

      return Erlang_Unicode["_build_error_tuple"](
        encodedPrefix,
        Type.list([Type.list([result.invalidData])]),
      );
    };

    const handleInvalidCodepoint = (result) => {
      const encodeValidChunks = (validChunks, outputEncoding) => {
        return encodeToTargetEncoding(
          Bitstring.concat(validChunks),
          outputEncoding,
        ).data;
      };

      const handleInvalidChunk = () => {
        const empty = Bitstring.fromBytes(new Uint8Array(0));
        empty.text = "";
        return empty;
      };

      const encodedPrefix =
        result.validChunks.length > 0
          ? encodeValidChunks(result.validChunks, outputEncoding)
          : handleInvalidChunk();

      // invalid_codepoint is due to invalid Unicode codepoint (too large)
      // Don't wrap - include directly with remaining elements
      const restElems = [result.data, ...result.remaining];

      return Erlang_Unicode["_build_error_tuple"](
        encodedPrefix,
        Type.list(restElems),
      );
    };

    // Process list recursively, accumulating valid chunks
    // Returns: {type: 'success', chunks: []} | {type: 'error', ...}
    const processListRecursive = (currentList, validChunks, remaining) => {
      if (!Type.isList(currentList)) {
        Erlang_Unicode["_raise_invalid_chardata/0"]();
      }

      const listData = currentList.data;

      for (let i = 0; i < listData.length; i++) {
        const elem = listData[i];
        const rest = [...listData.slice(i + 1), ...remaining];

        // Handle nested lists recursively
        if (Type.isList(elem)) {
          const nestedResult = processListRecursive(elem, validChunks, rest);
          if (nestedResult.type !== "success") return nestedResult;
          continue;
        }

        // Process element (binary or integer)
        const result = processElement(elem, outputEncoding);

        if (result.type === "invalid")
          Erlang_Unicode["_raise_invalid_chardata/0"]();

        if (result.type === "utf8error")
          return {
            type: "utf8error",
            validChunks,
            data: result.data,
          };

        if (result.type === "encoding_error")
          return {
            type: "encoding_error",
            validChunks,
            validData: result.validData,
            invalidData: result.invalidData,
          };

        if (result.type === "invalid_codepoint")
          return {
            type: "invalid_codepoint",
            validChunks,
            data: result.data,
            remaining: rest,
          };

        // Element is valid - accumulate it
        validChunks.push(result.data);
      }

      return {type: "success", validChunks};
    };

    const validChunks = [];
    const result = processListRecursive(list, validChunks, []);

    if (result.type === "utf8error")
      return handleUtf8Error(result.validChunks, result.data, outputEncoding);

    if (result.type === "encoding_error") return handleEncodingError(result);

    if (result.type === "invalid_codepoint")
      return handleInvalidCodepoint(result);

    // All elements processed successfully

    // If there are no valid chunks, return empty binary in target encoding
    if (validChunks.length === 0) return Type.bitstring("");

    // Concatenate valid chunks and encode to target encoding
    const binary = Bitstring.concat(validChunks);
    const encResult = encodeToTargetEncoding(binary, outputEncoding, false);

    return encResult.data;
  },
  // End _handle_list_input_cttb/2
  // Deps: [:unicode._build_error_tuple/2, :unicode._encode_to_target_encoding_cttb/3, :unicode._handle_utf8_error_cttb/3, :unicode._process_element_cttb/2, :unicode._raise_invalid_chardata/0]

  // Start _handle_utf8_error_cttb/3 (private helper)
  // Handles UTF-8 decoding errors during element processing.
  // Returns error or incomplete tuple with binary rest.
  "_handle_utf8_error_cttb/3": (validChunks, invalidBinary, outputEnc) => {
    const encodeToTargetEncoding = (utf8Binary, outEncoding, wasUtf8Input) =>
      Erlang_Unicode["_encode_to_target_encoding_cttb/3"](
        utf8Binary,
        outEncoding,
        wasUtf8Input,
      );

    const bytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](invalidBinary);
    const {validPrefix, invalidRest, isTruncated} =
      Erlang_Unicode["_split_at_utf8_validity_boundary/1"](bytes);

    // Encode valid prefix
    const totalChunks = [
      ...validChunks,
      validPrefix.bytes && validPrefix.bytes.length > 0 ? validPrefix : null,
    ].filter((chunk) => chunk !== null);

    const resultBinary =
      totalChunks.length > 0
        ? Bitstring.concat(totalChunks)
        : Type.bitstring("");

    const encResult = encodeToTargetEncoding(resultBinary, outputEnc, false);
    const encodedBinary = encResult.data;

    // Ensure invalid rest has text: false
    Bitstring.maybeSetBytesFromText(invalidRest);
    invalidRest.text = false;

    if (isTruncated)
      return Erlang_Unicode["_build_incomplete_tuple"](
        encodedBinary,
        invalidRest,
      );

    return Erlang_Unicode["_build_error_tuple"](
      encodedBinary,
      Type.list([invalidRest]),
    );
  },
  // End _handle_utf8_error_cttb/3
  // Deps: [:unicode._build_error_tuple/2, :unicode._build_incomplete_tuple/2, :unicode._encode_to_target_encoding_cttb/3, :unicode._ensure_bytes_from_binary/1, :unicode._split_at_utf8_validity_boundary/1]

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

  // Start _process_element_cttb/2 (private helper)
  // Processes a single element (binary or integer) from chardata.
  // Returns: { type: 'valid'|'invalid'|'utf8error'|'invalid_codepoint', data: result }
  "_process_element_cttb/2": (elem, outputEnc) => {
    const encodeToTargetEncoding = (utf8Binary, outEncoding, wasUtf8Input) =>
      Erlang_Unicode["_encode_to_target_encoding_cttb/3"](
        utf8Binary,
        outEncoding,
        wasUtf8Input,
      );

    const processBinaryResult = (elem, outputEnc) => {
      const text = Bitstring.toText(elem);
      // Valid UTF-8 binary
      if (text !== false) {
        const encResult = encodeToTargetEncoding(elem, outputEnc, false);
        if (encResult.type === "encoding_error") {
          return {
            type: "encoding_error",
            validData: encResult.validBinary,
            invalidData: encResult.invalidBinary,
          };
        }
        if (encResult.type === "error") {
          return {type: "utf8error", data: elem};
        }
        return {type: "valid", data: encResult.data};
      }
      // Invalid UTF-8 binary
      return {type: "utf8error", data: elem};
    };

    const isNonBinaryNonInteger = !Type.isBinary(elem) && !Type.isInteger(elem);

    // Reject non-binary, non-integer elements
    if (isNonBinaryNonInteger) return {type: "invalid"};

    // Process binaries: parse to UTF-8, then encode to target
    if (Type.isBinary(elem)) return processBinaryResult(elem, outputEnc);

    // Process integers (codepoints)
    const isSurrogateCodepoint = elem.value >= 0xd800 && elem.value <= 0xdfff;
    const isValidCodepoint = Bitstring.validateCodePoint(elem.value);

    if (!isValidCodepoint || isSurrogateCodepoint)
      return {type: "invalid_codepoint", data: elem};

    // Check if codepoint can be encoded to target encoding
    if (outputEnc.value === "latin1" && elem.value > 255) {
      // For integer codepoints that can't be encoded, keep the integer as-is
      return {
        type: "encoding_error",
        validData: null,
        invalidData: elem,
      };
    }

    // Convert codepoint to binary
    const binary = Erlang_Unicode["_convert_codepoint_to_binary/1"](elem);
    const encResult = encodeToTargetEncoding(binary, outputEnc, false);

    if (encResult.type === "ok") return {type: "valid", data: encResult.data};

    return {type: "invalid_codepoint", data: elem};
  },
  // End _process_element_cttb/2
  // Deps: [:unicode._convert_codepoint_to_binary/1, :unicode._encode_to_target_encoding_cttb/3]

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

  // Start _split_at_utf8_validity_boundary/1 (private helper)
  "_split_at_utf8_validity_boundary/1": (bytes) => {
    const {validLength, isTruncated} =
      Erlang_Unicode["_find_valid_utf8_prefix/1"](bytes);
    return {
      validPrefix: Bitstring.fromBytes(bytes.slice(0, validLength)),
      invalidRest: Bitstring.fromBytes(bytes.slice(validLength)),
      validLength,
      isTruncated,
    };
  },
  // End _split_at_utf8_validity_boundary/1
  // Deps: [:unicode._find_valid_utf8_prefix/1]

  // Start bom_to_encoding/1
  "bom_to_encoding/1": (binary) => {
    const bytes = Erlang_Unicode["_ensure_bytes_from_binary/1"](binary);

    // UTF-8 BOM: EF BB BF
    if (
      bytes.length >= 3 &&
      bytes[0] === 0xef &&
      bytes[1] === 0xbb &&
      bytes[2] === 0xbf
    ) {
      return Type.tuple([Type.atom("utf8"), Type.integer(3)]);
    }

    // UTF-32 big-endian BOM: 00 00 FE FF
    if (
      bytes.length >= 4 &&
      bytes[0] === 0x00 &&
      bytes[1] === 0x00 &&
      bytes[2] === 0xfe &&
      bytes[3] === 0xff
    ) {
      return Type.tuple([
        Type.tuple([Type.atom("utf32"), Type.atom("big")]),
        Type.integer(4),
      ]);
    }

    // UTF-32 little-endian BOM: FF FE 00 00
    if (
      bytes.length >= 4 &&
      bytes[0] === 0xff &&
      bytes[1] === 0xfe &&
      bytes[2] === 0x00 &&
      bytes[3] === 0x00
    ) {
      return Type.tuple([
        Type.tuple([Type.atom("utf32"), Type.atom("little")]),
        Type.integer(4),
      ]);
    }

    // UTF-16 big-endian BOM: FE FF
    if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
      return Type.tuple([
        Type.tuple([Type.atom("utf16"), Type.atom("big")]),
        Type.integer(2),
      ]);
    }

    // UTF-16 little-endian BOM: FF FE
    if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
      return Type.tuple([
        Type.tuple([Type.atom("utf16"), Type.atom("little")]),
        Type.integer(2),
      ]);
    }

    return Type.tuple([Type.atom("latin1"), Type.integer(0)]);
  },
  // End bom_to_encoding/1
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
    const isNotBinaryListOrInteger =
      !Type.isBinary(input) && !Type.isList(input) && !Type.isInteger(input);

    // Validate input type
    if (isNotBinaryListOrInteger) Erlang_Unicode["_raise_invalid_chardata/0"]();

    // Dispatch to appropriate handler
    if (Type.isInteger(input))
      return Erlang_Unicode["_handle_integer_input_cttb/3"](
        input,
        inputEncoding,
        outputEncoding,
      );

    if (Type.isBinary(input))
      return Erlang_Unicode["_handle_binary_input_cttb/3"](
        input,
        inputEncoding,
        outputEncoding,
      );

    return Erlang_Unicode["_handle_list_input_cttb/2"](input, outputEncoding);
  },
  // End characters_to_binary/3
  // Deps: [:unicode._handle_binary_input_cttb/3, :unicode._handle_integer_input_cttb/3, :unicode._handle_list_input_cttb/2, :unicode._raise_invalid_chardata/0]

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
      const bytes =
        Erlang_Unicode["_ensure_bytes_from_binary/1"](invalidBinary);
      const {validPrefix, invalidRest, validLength, isTruncated} =
        Erlang_Unicode["_split_at_utf8_validity_boundary/1"](bytes);

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
      const bytes =
        Erlang_Unicode["_ensure_bytes_from_binary/1"](invalidBinary);
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
  // Deps: [:unicode._convert_binary_to_codepoints/3, :unicode._convert_codepoint_to_binary/1, :unicode._ensure_bytes_from_binary/1, :unicode._find_valid_utf8_prefix/1, :unicode._process_chardata_list/3, :unicode._raise_invalid_chardata/0, :unicode._split_at_utf8_validity_boundary/1, :lists.flatten/1]

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

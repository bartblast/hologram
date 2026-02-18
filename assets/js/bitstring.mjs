"use strict";

import ERTS from "./erts.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Bitstring {
  static #decoder = ERTS.utf8Decoder;
  static #encoder = new TextEncoder("utf-8");

  static calculateBitCount(bitstring) {
    if (bitstring.bytes !== null) {
      const completeByteCount =
        bitstring.leftoverBitCount === 0
          ? bitstring.bytes.length
          : bitstring.bytes.length - 1;

      return 8 * completeByteCount + bitstring.leftoverBitCount;
    }

    return 8 * $.calculateTextByteCount(bitstring.text);
  }

  static calculateSegmentBitCount(segment) {
    const size = $.resolveSegmentSize(segment);
    if (size === null) return null;

    const unit = $.resolveSegmentUnit(segment);
    if (unit === null) return null;

    return size * unit;
  }

  static calculateTextByteCount(text) {
    return $.#encoder.encode(text).length;
  }

  // Performs structural comparison of two bitstrings consistent with Elixir's behavior.
  // See: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // "Bitstrings are compared byte by byte, incomplete bytes are compared bit by bit."
  // Returns -1 if bitstring1 < bitstring2, 0 if equal, 1 if bitstring1 > bitstring2
  static compare(bitstring1, bitstring2) {
    // Fast path: text-based comparison for identical text representations
    if (bitstring1.text !== null && bitstring2.text !== null) {
      if (
        bitstring1.text === bitstring2.text &&
        bitstring1.leftoverBitCount === bitstring2.leftoverBitCount
      ) {
        return 0;
      }
      // If both are text-based but different, fall through to byte comparison
    }

    // Ensure both bitstrings have bytes representation
    $.maybeSetBytesFromText(bitstring1);
    $.maybeSetBytesFromText(bitstring2);

    const bytes1 = bitstring1.bytes;
    const bytes2 = bitstring2.bytes;
    const leftover1 = bitstring1.leftoverBitCount;
    const leftover2 = bitstring2.leftoverBitCount;

    // Fast path: if both have no leftover bits, use optimized byte array comparison
    if (leftover1 === 0 && leftover2 === 0) {
      const len1 = bytes1.length;
      const len2 = bytes2.length;
      const minLen = Math.min(len1, len2);

      // Compare bytes in chunks for better performance
      let i = 0;

      // Process 4 bytes at a time when possible (unrolled loop)
      const end4 = minLen - (minLen % 4);
      for (; i < end4; i += 4) {
        if (bytes1[i] !== bytes2[i]) return bytes1[i] < bytes2[i] ? -1 : 1;
        if (bytes1[i + 1] !== bytes2[i + 1])
          return bytes1[i + 1] < bytes2[i + 1] ? -1 : 1;
        if (bytes1[i + 2] !== bytes2[i + 2])
          return bytes1[i + 2] < bytes2[i + 2] ? -1 : 1;
        if (bytes1[i + 3] !== bytes2[i + 3])
          return bytes1[i + 3] < bytes2[i + 3] ? -1 : 1;
      }

      // Handle remaining bytes
      for (; i < minLen; i++) {
        if (bytes1[i] !== bytes2[i]) {
          return bytes1[i] < bytes2[i] ? -1 : 1;
        }
      }

      // All common bytes are equal, compare lengths
      return len1 === len2 ? 0 : len1 < len2 ? -1 : 1;
    }

    // Complex case: handle leftover bits
    const completeBytes1 = leftover1 === 0 ? bytes1.length : bytes1.length - 1;
    const completeBytes2 = leftover2 === 0 ? bytes2.length : bytes2.length - 1;
    const minCompleteBytes = Math.min(completeBytes1, completeBytes2);

    // Compare complete bytes first
    for (let i = 0; i < minCompleteBytes; i++) {
      if (bytes1[i] !== bytes2[i]) {
        return bytes1[i] < bytes2[i] ? -1 : 1;
      }
    }

    // Handle case where one bitstring has more complete bytes
    if (completeBytes1 !== completeBytes2) {
      const isFirstLonger = completeBytes1 > completeBytes2;
      const longerBytes = isFirstLonger ? bytes1 : bytes2;
      const shorterLeftover = isFirstLonger ? leftover2 : leftover1;
      const nextByte = longerBytes[minCompleteBytes];

      if (shorterLeftover === 0) {
        // Shorter bitstring has no more bits
        return isFirstLonger ? 1 : -1;
      }

      // Compare next byte from longer with leftover bits from shorter
      const shorterBytes = isFirstLonger ? bytes2 : bytes1;
      const shorterLastByte = shorterBytes[shorterBytes.length - 1];
      const mask = 0xff << (8 - shorterLeftover);
      const shorterMasked = shorterLastByte & mask;

      if (nextByte !== shorterMasked) {
        const result = nextByte < shorterMasked ? -1 : 1;
        return isFirstLonger ? result : -result;
      }

      // Equal up to leftover bits, longer one wins
      return isFirstLonger ? 1 : -1;
    }

    // Both have same number of complete bytes, compare leftover bits
    if (leftover1 === 0) {
      return leftover2 === 0 ? 0 : -1;
    }
    if (leftover2 === 0) {
      return 1;
    }

    // Both have leftover bits
    const lastByte1 = bytes1[bytes1.length - 1];
    const lastByte2 = bytes2[bytes2.length - 1];
    const minLeftover = Math.min(leftover1, leftover2);
    const mask = 0xff << (8 - minLeftover);
    const masked1 = lastByte1 & mask;
    const masked2 = lastByte2 & mask;

    if (masked1 !== masked2) {
      return masked1 < masked2 ? -1 : 1;
    }

    // Common bits equal, more leftover bits wins
    return leftover1 === leftover2 ? 0 : leftover1 < leftover2 ? -1 : 1;
  }

  static concat(bitstrings) {
    // Fast path: if a single bitstring is given return it as is
    if (bitstrings.length === 1) {
      return bitstrings[0];
    }

    // Fast path: if all bitstrings are text-based join them
    // Notice: this also covers the case when an empty array is given (an empty bitstring is returned)
    if (bitstrings.every((bs) => bs.text !== null)) {
      const text = bitstrings.map((bs) => bs.text).join("");
      return $.fromText(text);
    }

    bitstrings.forEach((bs) => $.maybeSetBytesFromText(bs));

    // Fast path: no bitstrings with leftover bits
    if (bitstrings.every((bs) => bs.leftoverBitCount === 0)) {
      return $.#concatBitstringsWithoutLeftoverBits(bitstrings);
    }

    // Complex case: handle leftover bits

    const totalBitCount = bitstrings.reduce(
      (acc, bs) => acc + $.calculateBitCount(bs),
      0,
    );

    const resultByteCount = Math.ceil(totalBitCount / 8);
    const resultLeftoverBitCount = totalBitCount % 8;
    const resultBytes = new Uint8Array(resultByteCount);

    let bitOffset = 0;

    for (let i = 0; i < bitstrings.length; i++) {
      const bs = bitstrings[i];
      const bsBitCount = $.calculateBitCount(bs);

      if (bsBitCount === 0) continue;

      const byteOffset = bitOffset >>> 3; // Integer division by 8

      if (bitOffset % 8 === 0) {
        // If we're at a byte boundary, we can use a fast path
        $.#appendBitstringAtByteBoundary(resultBytes, byteOffset, bs);
      } else {
        // We're not at a byte boundary - need to shift bits
        $.#appendBitstringNotAtByteBoundary(
          resultBytes,
          byteOffset,
          bitOffset,
          bs,
        );
      }

      bitOffset += bsBitCount;
    }

    return {
      type: "bitstring",
      text: null,
      bytes: resultBytes,
      leftoverBitCount: resultLeftoverBitCount,
      hex: null,
    };
  }

  // TODO: support utf8, utf16, utf32 modifiers
  static decodeSegmentChunk(segment, chunk) {
    let endianness, signedness;

    switch (segment.type) {
      case "binary":
      case "bitstring":
        return chunk;

      case "float":
        endianness = segment.endianness || "big";
        return $.toFloat(chunk, endianness);

      case "integer":
        signedness = segment.signedness || "unsigned";
        endianness = segment.endianness || "big";
        return $.toInteger(chunk, signedness, endianness);

      default:
        throw new HologramInterpreterError(
          `${segment.type} segment type modifier is not yet implemented in Hologram`,
        );
    }
  }

  // Decodes a UTF-8 sequence starting at the given position.
  // Returns the decoded Unicode code point value.
  // bytes: Uint8Array containing the UTF-8 encoded data
  // start: byte index where the sequence begins
  // length: number of bytes in the UTF-8 sequence (1-4)
  static decodeUtf8CodePoint(bytes, start, length) {
    if (length === 1) return bytes[start];

    // First byte masks: 2-byte=0x1f, 3-byte=0x0f, 4-byte=0x07
    const firstByteMasks = {2: 0x1f, 3: 0x0f, 4: 0x07};

    let codePoint = bytes[start] & firstByteMasks[length];

    // Process continuation bytes (all use 0x3f mask, shift by 6 each)
    for (let i = 1; i < length; i++) {
      codePoint = (codePoint << 6) | (bytes[start + i] & 0x3f);
    }

    return codePoint;
  }

  static fromBits(bits) {
    const bitCount = bits.length;
    const byteCount = Math.ceil(bitCount / 8);
    const leftoverBitCount = bitCount % 8;
    const bytes = new Uint8Array(byteCount);

    // Process 8 bytes at a time when possible
    let byteIndex = 0;
    let bitIndex = 0;

    // Fast path for byte-aligned chunks
    while (bitIndex + 8 <= bitCount) {
      bytes[byteIndex++] =
        (bits[bitIndex] << 7) |
        (bits[bitIndex + 1] << 6) |
        (bits[bitIndex + 2] << 5) |
        (bits[bitIndex + 3] << 4) |
        (bits[bitIndex + 4] << 3) |
        (bits[bitIndex + 5] << 2) |
        (bits[bitIndex + 6] << 1) |
        bits[bitIndex + 7];
      bitIndex += 8;
    }

    // Handle remaining bits if any
    if (bitIndex < bitCount) {
      let lastByte = 0;

      for (let j = 0; j < leftoverBitCount; j++) {
        if (bits[bitIndex + j]) {
          lastByte |= 1 << (7 - j);
        }
      }
      bytes[byteIndex] = lastByte;
    }

    return {
      type: "bitstring",
      text: null,
      bytes,
      leftoverBitCount,
      hex: null,
    };
  }

  static fromBytes(bytes) {
    const uint8Bytes =
      bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

    return {
      type: "bitstring",
      text: null,
      bytes: uint8Bytes,
      leftoverBitCount: 0,
      hex: null,
    };
  }

  static fromSegments(segments) {
    const bitstrings = segments.map((segment) => {
      switch (segment.value.type) {
        case "bitstring":
          return $.fromSegmentWithBitstringValue(segment);

        case "float":
          return $.fromSegmentWithFloatValue(segment);

        case "integer":
          return $.fromSegmentWithIntegerValue(segment);

        case "string":
          return $.fromSegmentWithStringValue(segment);
      }
    });

    return $.concat(bitstrings);
  }

  static fromSegmentWithBitstringValue(segment) {
    // Fast path: if no size specified, use the entire bitstring
    if (segment.size === null) {
      return segment.value;
    }

    // For bitstrings "unit" is always 1, so we can use just "size"
    return $.takeChunk(segment.value, 0, Number(segment.size.value));
  }

  static fromSegmentWithFloatValue(segment) {
    let value;

    if (segment.value.type === "float") {
      value = segment.value.value;
    } else {
      // integer
      value = Number(segment.value.value);
    }

    const isLittleEndian = $.#isLittleEndian(segment);

    const bitCount = $.calculateSegmentBitCount(segment);
    const byteCount = bitCount / 8;
    const buffer = new ArrayBuffer(byteCount);
    const dataView = new DataView(buffer);

    if (bitCount === 64) {
      dataView.setFloat64(0, value, isLittleEndian);
    } else if (bitCount === 32) {
      dataView.setFloat32(0, value, isLittleEndian);
    } else {
      // DataView.setFloat16() has limited availability in browsers
      $.#setFloat16(dataView, value, isLittleEndian);
    }

    return {
      type: "bitstring",
      text: null,
      bytes: new Uint8Array(buffer),
      leftoverBitCount: 0,
      hex: null,
    };
  }

  // TODO: support utf16 and utf32 type modifiers
  static fromSegmentWithIntegerValue(segment) {
    const value = segment.value.value;

    if (segment.type === "utf8") {
      return {
        type: "bitstring",
        text: String.fromCodePoint(Number(value)),
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };
    }

    if (
      value >= BigInt(Number.MIN_SAFE_INTEGER) &&
      value <= BigInt(Number.MAX_SAFE_INTEGER)
    ) {
      return $.#fromSegmentWithIntegerWithinNumberRangeValue(segment);
    }

    return $.#fromSegmentWithIntegerOutsideNumberRangeValue(segment);
  }

  static fromSegmentWithStringValue(segment) {
    const valueStr = segment.value.value;

    // TODO: this won't work correctly for utf16 and utf32
    // Fast path: if no size specified, use the entire string
    if (segment.size === null) {
      return {
        type: "bitstring",
        text: valueStr,
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };
    }

    // Calculate the bit count from size and unit (do this before encoding for potential early returns)
    const bitCount = $.calculateSegmentBitCount(segment);
    const completeBytes = Math.floor(bitCount / 8);
    const leftoverBits = bitCount % 8;

    const byteLength = $.calculateTextByteCount(valueStr);

    // If we know we need the complete string and no leftover bits, avoid encoding
    if (completeBytes === byteLength && leftoverBits === 0) {
      return {
        type: "bitstring",
        text: valueStr,
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };
    }

    const sourceBytes = $.#encoder.encode(valueStr);

    // Fast path: if we need all complete bytes but no leftover bits
    if (leftoverBits === 0) {
      // We can use a subarray view of the original bytes to avoid copying
      return {
        type: "bitstring",
        text: null,
        bytes: sourceBytes.subarray(0, completeBytes),
        leftoverBitCount: 0,
        hex: null,
      };
    }

    const totalBytes = completeBytes + 1;
    const bytes = new Uint8Array(totalBytes);

    // Micro-optimization: If we only need a few bytes, avoid the set() operation overhead
    if (completeBytes <= 4) {
      // Manual copy for small arrays - can be faster than set() due to function call overhead
      for (let i = 0; i < completeBytes; i++) {
        bytes[i] = sourceBytes[i];
      }
    } else {
      // Use set() for larger arrays - more efficient for bulk operations
      bytes.set(sourceBytes.subarray(0, completeBytes));
    }

    // We take the leftmost (most significant bits) as the leftover bits
    const mask = 0xff << (8 - leftoverBits);
    bytes[completeBytes] = sourceBytes[completeBytes] & mask;

    return {
      type: "bitstring",
      text: null,
      bytes,
      leftoverBitCount: leftoverBits,
      hex: null,
    };
  }

  static fromText(text) {
    return {
      type: "bitstring",
      text,
      bytes: null,
      leftoverBitCount: 0,
      hex: null,
    };
  }

  // Determines the expected UTF-8 sequence length from the leader byte.
  // Returns false for invalid leader bytes (e.g., 0xC0, 0xC1, 0xF5+).
  static getUtf8SequenceLength(leaderByte) {
    if ((leaderByte & 0x80) === 0) return 1; // 0xxxxxxx: ASCII
    if (leaderByte === 0xc0 || leaderByte === 0xc1) return false; // Invalid: overlong encoding
    if ((leaderByte & 0xe0) === 0xc0) return 2; // 110xxxxx: 2-byte
    if ((leaderByte & 0xf0) === 0xe0) return 3; // 1110xxxx: 3-byte
    if (leaderByte >= 0xf5) return false; // Invalid: > U+10FFFF
    if ((leaderByte & 0xf8) === 0xf0) return 4; // 11110xxx: 4-byte
    return false; // Invalid leader byte
  }

  static isEmpty(bitstring) {
    return bitstring.text === "" || bitstring.bytes?.length === 0;
  }

  // See: String.printable?/2
  // https://github.com/elixir-lang/elixir/blob/6bfb95ab884f11475de6da3f99c6528938e025a8/lib/elixir/lib/string.ex#L322
  static isPrintableCodePoint(codePoint) {
    // 0x20 = 32, 0x7E = 126
    if (codePoint >= 32 && codePoint <= 126) {
      return true;
    }

    // ?\n = 10
    // ?\r = 13
    // ?\t = 9
    // ?\v = 11
    // ?\b = 8
    // ?\f = 12
    // ?\e = 27
    // ?\d = 127
    // ?\a = 7
    if (
      codePoint === 10 ||
      codePoint === 13 ||
      codePoint === 9 ||
      codePoint === 11 ||
      codePoint === 8 ||
      codePoint === 12 ||
      codePoint === 27 ||
      codePoint === 127 ||
      codePoint === 7
    ) {
      return true;
    }

    // 0xA0 = 160, 0xD7FF = 55295
    if (codePoint >= 160 && codePoint <= 55295) {
      return true;
    }

    // 0xE000 = 57344, 0xFFFD = 65533
    if (codePoint >= 57344 && codePoint <= 65533) {
      return true;
    }

    // 0x10000 = 65536, 0x10FFFF = 1114111
    if (codePoint >= 65536 && codePoint <= 1114111) {
      return true;
    }

    return false;
  }

  static isPrintableText(bitstring) {
    if (bitstring.leftoverBitCount !== 0) {
      return false;
    }

    $.maybeSetTextFromBytes(bitstring);

    if (bitstring.text === false) {
      return false;
    }

    for (const char of bitstring.text) {
      if (!$.isPrintableCodePoint(char.codePointAt(0))) {
        return false;
      }
    }

    return true;
  }

  static isText(bitstring) {
    if (!Type.isBinary(bitstring)) {
      return false;
    }

    $.maybeSetTextFromBytes(bitstring);
    return bitstring.text !== false;
  }

  // Validates that a code point is within UTF-8 rules:
  // - Not an overlong encoding (using more bytes than necessary)
  // - Not a UTF-16 surrogate (U+D800–U+DFFF)
  // - Not above maximum Unicode (U+10FFFF)
  static isValidUtf8CodePoint(codePoint, encodingLength) {
    // Check for overlong encodings (security issue)
    const minValueForLength = {1: 0, 2: 0x80, 3: 0x800, 4: 0x10000};

    // Reject code points that could have been encoded with fewer bytes (overlong)
    if (codePoint < minValueForLength[encodingLength]) return false;
    // Reject UTF-16 surrogates (U+D800–U+DFFF)
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) return false;
    // Reject code points beyond Unicode range (> U+10FFFF)
    if (codePoint > 0x10ffff) return false;

    return true;
  }

  // Checks if a byte is a valid UTF-8 continuation byte (10xxxxxx).
  static isValidUtf8ContinuationByte(byte) {
    return (byte & 0xc0) === 0x80;
  }

  // Validates a UTF-8 sequence at the given position assuming the leader byte
  // has already been confirmed valid for `length` (e.g. via getUtf8SequenceLength).
  // Checks: sufficient bytes, valid continuation bytes, and valid code point.
  // Precondition: `length` is the value returned by getUtf8SequenceLength(bytes[start]).
  static isValidUtf8Sequence(bytes, start, length) {
    // Check if we have enough bytes
    if (start + length > bytes.length) return false;

    // Verify all continuation bytes have correct pattern (10xxxxxx)
    for (let i = 1; i < length; i++) {
      if (!$.isValidUtf8ContinuationByte(bytes[start + i])) return false;
    }

    // Decode and validate the code point value
    const codePoint = $.decodeUtf8CodePoint(bytes, start, length);

    return $.isValidUtf8CodePoint(codePoint, length);
  }

  static maybeResolveHex(bitstring) {
    if (bitstring.hex === null) {
      $.maybeSetBytesFromText(bitstring);

      let hex = "";
      const bytes = bitstring.bytes;

      for (let i = 0; i < bytes.length; i++) {
        hex += bytes[i].toString(16).padStart(2, "0");
      }

      bitstring.hex = hex;
    }
  }

  static maybeSetBytesFromText(bitstring) {
    if (bitstring.bytes === null) {
      bitstring.bytes = $.#encoder.encode(bitstring.text);
    }
  }

  static maybeSetTextFromBytes(bitstring) {
    if (bitstring.text === null) {
      try {
        bitstring.text = $.#decoder.decode(bitstring.bytes);
      } catch {
        bitstring.text = false;
      }
    }
  }

  // TODO: support utf8, utf16 and utf32 type modifiers
  static resolveSegmentSize(segment) {
    if (segment.size !== null) {
      return Number(segment.size.value);
    }

    switch (segment.type) {
      case "binary":
        if (segment.value.type === "string") {
          return $.calculateTextByteCount(segment.value.value);
        }

        // bitstring
        if (segment.value.text !== null) {
          return $.calculateTextByteCount(segment.value.text);
        }

        // bitstring
        return segment.value.bytes.length;

      case "float":
        return 64;

      case "integer":
        return 8;

      default:
        return null;
    }
  }

  static resolveSegmentUnit(segment) {
    if (segment.unit !== null) {
      return Number(segment.unit);
    }

    return segment.type === "binary" ? 8 : 1;
  }

  static serialize(bitstring) {
    if ($.isEmpty(bitstring)) {
      return "b";
    }

    $.maybeResolveHex(bitstring);

    return `b${bitstring.leftoverBitCount}${bitstring.hex}`;
  }

  static takeChunk(bitstring, chunkOffset, chunkSize) {
    const bitstringBitCount = $.calculateBitCount(bitstring);

    // Early return for taking the entire bitstring
    if (chunkOffset === 0 && chunkSize === bitstringBitCount) {
      return bitstring;
    }

    $.maybeSetBytesFromText(bitstring);

    const startByteIndex = Math.floor(chunkOffset / 8);
    const startBitOffset = chunkOffset % 8;
    const resultByteCount = Math.ceil(chunkSize / 8);
    const resultLeftoverBits = chunkSize % 8;

    // Fast path: if byte-aligned and no leftover bits
    if (startBitOffset === 0 && resultLeftoverBits === 0) {
      return {
        type: "bitstring",
        text: null,
        bytes: bitstring.bytes.subarray(
          startByteIndex,
          startByteIndex + resultByteCount,
        ),
        leftoverBitCount: 0,
        hex: null,
      };
    }

    const resultBytes = new Uint8Array(resultByteCount);

    if (startBitOffset === 0) {
      // Byte-aligned with leftover bits

      resultBytes.set(
        bitstring.bytes.subarray(
          startByteIndex,
          startByteIndex + resultByteCount,
        ),
      );

      resultBytes[resultByteCount - 1] &= 0xff << (8 - resultLeftoverBits);
    } else {
      // Non-byte-aligned

      const rightShift = 8 - startBitOffset;
      const leftShift = startBitOffset;
      const bytes = bitstring.bytes; // Local reference to array performance optimization

      for (let i = 0; i < resultByteCount; i++) {
        const firstByte = bytes[startByteIndex + i];
        const secondByte = bytes[startByteIndex + i + 1];

        resultBytes[i] =
          ((firstByte << leftShift) | (secondByte >>> rightShift)) & 0xff;
      }

      // Mask out extra bits in the last byte if we have leftover bits
      if (resultLeftoverBits > 0) {
        resultBytes[resultByteCount - 1] &= 0xff << (8 - resultLeftoverBits);
      }
    }

    return {
      type: "bitstring",
      text: null,
      bytes: resultBytes,
      leftoverBitCount: resultLeftoverBits,
      hex: null,
    };
  }

  static toCodepoints(bitstring) {
    $.maybeSetTextFromBytes(bitstring);
    return Type.charlist(bitstring.text);
  }

  static toFloat(bitstring, endianness) {
    $.maybeSetBytesFromText(bitstring);

    const bytes = bitstring.bytes;
    const byteCount = bytes.length;
    const isLittleEndian = endianness === "little";

    let result;

    if (byteCount === 8) {
      // 64-bit float
      const buffer = new ArrayBuffer(8);
      const view = new Uint8Array(buffer);
      view.set(bytes);
      result = new DataView(buffer).getFloat64(0, isLittleEndian);
    } else if (byteCount === 4) {
      // 32-bit float
      const buffer = new ArrayBuffer(4);
      const view = new Uint8Array(buffer);
      view.set(bytes);
      result = new DataView(buffer).getFloat32(0, isLittleEndian);
    } else {
      // 16-bit float - needs manual conversion as JavaScript doesn't natively support Float16
      result = $.#decodeFloat16(bytes, isLittleEndian);
    }

    return Type.float(result);
  }

  static toInteger(bitstring, signedness, endianness) {
    $.maybeSetBytesFromText(bitstring);

    const bytes = bitstring.bytes;
    const byteCount = bytes.length;

    if (byteCount === 0) {
      return Type.integer(0n);
    }

    const leftoverBitCount = bitstring.leftoverBitCount;
    const isSigned = signedness === "signed";

    // Fast path for single byte with no leftover bits
    if (byteCount === 1 && leftoverBitCount === 0) {
      const value = bytes[0];

      return Type.integer(
        isSigned && value & 0x80 ? BigInt(value - 256) : BigInt(value),
      );
    }

    const isLittleEndian = endianness === "little";

    if (leftoverBitCount === 0) {
      return $.#toIntegerFromBitstringWithoutLeftoverBits(
        bitstring,
        isSigned,
        isLittleEndian,
      );
    }

    return $.#toIntegerFromBitstringWithLeftoverBits(
      bitstring,
      isSigned,
      isLittleEndian,
    );
  }

  static toText(bitstring) {
    $.maybeSetTextFromBytes(bitstring);

    return bitstring.text;
  }

  static validateCodePoint(codePoint) {
    if (typeof codePoint === "bigint") {
      codePoint = Number(codePoint);
    }

    try {
      String.fromCodePoint(codePoint);
      return true;
    } catch (error) {
      if (error instanceof RangeError) {
        return false;
      } else {
        throw error;
      }
    }
  }

  static validateSegment(segment, index) {
    switch (segment.type) {
      case "binary":
        return $.#validateSegmentWithBinaryType(segment, index);

      case "bitstring":
        return $.#validateSegmentWithBitstringType(segment, index);

      case "float":
        return $.#validateSegmentWithFloatType(segment, index);

      case "integer":
        return $.#validateSegmentWithIntegerType(segment, index);

      case "utf8":
      case "utf16":
      case "utf32":
        return $.#validateSegmentWithUtfType(segment, index);
    }
  }

  static #appendBitstringAtByteBoundary(resultBytes, byteOffset, bitstring) {
    const bytes = bitstring.bytes;
    const leftoverBitCount = bitstring.leftoverBitCount;

    if (leftoverBitCount === 0) {
      // If no leftover bits in this bitstring, copy directly
      resultBytes.set(bytes, byteOffset);
    } else {
      const totalByteCount = bytes.length;
      const completeByteCount = totalByteCount - 1;

      if (completeByteCount > 0) {
        resultBytes.set(bytes.subarray(0, completeByteCount), byteOffset);
      }

      // Apply a mask to only include the leftover bits in the last byte
      const lastByte = bytes[totalByteCount - 1];
      const lastByteOffset = byteOffset + completeByteCount;
      const leftoverBitsMask = 0xff << (8 - leftoverBitCount);
      const maskedLastByte = lastByte & leftoverBitsMask;

      // Place leftover bits in the correct position
      resultBytes[lastByteOffset] = maskedLastByte;
    }
  }

  static #appendBitstringNotAtByteBoundary(
    resultBytes,
    byteOffset,
    bitOffset,
    bitstring,
  ) {
    const bytes = bitstring.bytes;
    const leftoverBitCount = bitstring.leftoverBitCount;
    const bitPositionInByte = bitOffset & 7; // Modulo 8 (position within byte)
    const bitsToShiftRight = bitPositionInByte; // How many bits to shift right when adding to current byte
    const bitsToShiftLeft = 8 - bitsToShiftRight; // How many bits to shift left when adding to next byte

    // Calculate how many complete bytes we have in the source bitstring
    const completeByteCount =
      leftoverBitCount === 0 ? bytes.length : bytes.length - 1;

    // Process all complete bytes in the source bitstring
    for (let i = 0; i < completeByteCount; i++) {
      const currentByte = bytes[i];

      // Add high bits to current byte (may already have bits)
      resultBytes[byteOffset + i] |= currentByte >>> bitsToShiftRight;

      // Add low bits to next byte (if we're not byte-aligned)
      if (bitsToShiftRight > 0) {
        resultBytes[byteOffset + i + 1] =
          (currentByte << bitsToShiftLeft) & 0xff;
      }
    }

    // Handle last byte with leftover bits if any
    if (leftoverBitCount > 0) {
      const lastByte = bytes[completeByteCount];

      // Create a mask to extract only the valid leftover bits from the most significant bits
      const leftoverBitsMask = 0xff << (8 - leftoverBitCount);
      const maskedLastByte = lastByte & leftoverBitsMask;

      // Add high bits of the last byte to current position
      resultBytes[byteOffset + completeByteCount] |=
        maskedLastByte >>> bitsToShiftRight;

      // Add low bits of the last byte to next position if we're not byte-aligned
      if (bitsToShiftRight > 0) {
        resultBytes[byteOffset + completeByteCount + 1] |=
          (maskedLastByte << bitsToShiftLeft) & 0xff;
      }
    }
  }

  static #concatBitstringsWithoutLeftoverBits(bitstrings) {
    const totalByteCount = bitstrings.reduce((acc, bs) => {
      return acc + bs.bytes.length;
    }, 0);

    const resultBytes = new Uint8Array(totalByteCount);
    let offset = 0;

    for (let i = 0; i < bitstrings.length; i++) {
      const bs = bitstrings[i];
      resultBytes.set(bs.bytes, offset);
      offset += bs.bytes.length;
    }

    return {
      type: "bitstring",
      text: null,
      bytes: resultBytes,
      leftoverBitCount: 0,
      hex: null,
    };
  }

  static #decodeFloat16(bytes, isLittleEndian) {
    const byte1 = isLittleEndian ? bytes[1] : bytes[0];
    const byte2 = isLittleEndian ? bytes[0] : bytes[1];

    const sign = byte1 & 0x80 ? -1 : 1;
    const exponent = (byte1 & 0x7c) >> 2;
    const fraction = ((byte1 & 0x03) << 8) | byte2;

    // Handle special cases
    if (exponent === 0) {
      if (fraction === 0) {
        return sign * 0; // Signed zero
      }

      // Denormalized number
      return sign * Math.pow(2, -14) * (fraction / 1024);
    }

    // Normalized number
    return sign * Math.pow(2, exponent - 15) * (1 + fraction / 1024);
  }

  static #fromSegmentWithIntegerWithinNumberRangeValue(segment) {
    const numberValue = Number(segment.value.value);
    const isLittleEndian = $.#isLittleEndian(segment);

    const bitCount = $.calculateSegmentBitCount(segment);
    const completeBytes = Math.floor(bitCount / 8);
    const leftoverBits = bitCount % 8;
    const totalBytes = completeBytes + (leftoverBits > 0 ? 1 : 0);

    const buffer = new ArrayBuffer(totalBytes);
    const bytesArray = new Uint8Array(buffer);
    const dataView = new DataView(buffer);

    // Fast path for standard bit counts
    if (bitCount === 8) {
      dataView.setUint8(0, numberValue & 0xff);

      return {
        type: "bitstring",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
        hex: null,
      };
    } else if (bitCount === 16 && completeBytes === 2) {
      dataView.setUint16(0, numberValue & 0xffff, isLittleEndian);

      return {
        type: "bitstring",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
        hex: null,
      };
    } else if (bitCount === 32 && completeBytes === 4) {
      dataView.setUint32(0, numberValue & 0xffffffff, isLittleEndian);

      return {
        type: "bitstring",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
        hex: null,
      };
    }

    // Hybrid approach: bitwise operations for small integers, division for larger ones
    const usesBitwiseOps = Math.abs(numberValue) < 0x100000000; // 2^32

    if (isLittleEndian) {
      // Little endian: LSB first

      let remainingValue = numberValue;

      for (let i = 0; i < completeBytes; i++) {
        if (usesBitwiseOps) {
          bytesArray[i] = remainingValue & 0xff;
          remainingValue = remainingValue >>> 8;
        } else {
          bytesArray[i] = remainingValue % 256;
          remainingValue = Math.floor(remainingValue / 256);
        }
      }

      // Handle leftover bits
      if (leftoverBits > 0) {
        const shiftAmount = 8 - leftoverBits;

        bytesArray[completeBytes] =
          (remainingValue & ((1 << leftoverBits) - 1)) << shiftAmount;
      }
    } else {
      // Big endian: MSB first

      if (usesBitwiseOps) {
        // Fast bit shifting approach for small integers

        const totalBitsInInteger = 32;

        // Calculate shift to align with MSB

        const initialShift = totalBitsInInteger - bitCount;

        let shiftedValue =
          initialShift > 0 ? numberValue << initialShift : numberValue;

        // For complete bytes
        for (let i = 0; i < completeBytes; i++) {
          bytesArray[i] = (shiftedValue >>> (totalBitsInInteger - 8)) & 0xff;
          shiftedValue = shiftedValue << 8;
        }

        // Handle leftover bits
        if (leftoverBits > 0) {
          bytesArray[completeBytes] =
            (shiftedValue >>> (totalBitsInInteger - 8)) & 0xff;
        }
      } else {
        // Division approach for larger integers

        let remainingValue = numberValue;

        // For big-endian, we need to start with the most significant bits
        // Calculate bytes from most significant to least significant
        for (let i = 0; i < completeBytes; i++) {
          // Calculate how many bits we still need to shift
          const bitsToShift = (completeBytes - i - 1) * 8 + leftoverBits;

          // Create a divisor based on that shift
          const divisor = Math.pow(2, bitsToShift);

          // Extract the current byte
          const byteValue = Math.floor(remainingValue / divisor);
          bytesArray[i] = byteValue & 0xff;

          // Remove the processed bits
          remainingValue = remainingValue % divisor;
        }

        // Handle leftover bits
        if (leftoverBits > 0) {
          // For leftover bits, we shift them to the most significant bits of the last byte
          bytesArray[completeBytes] =
            (remainingValue << (8 - leftoverBits)) & 0xff;
        }
      }
    }

    return {
      type: "bitstring",
      text: null,
      bytes: bytesArray,
      leftoverBitCount: leftoverBits,
      hex: null,
    };
  }

  static #fromSegmentWithIntegerOutsideNumberRangeValue(segment) {
    const value = segment.value.value;
    const isLittleEndian = $.#isLittleEndian(segment);

    const bitCount = $.calculateSegmentBitCount(segment);
    const completeBytes = Math.floor(bitCount / 8);
    const leftoverBits = bitCount % 8;
    const totalBytes = completeBytes + (leftoverBits > 0 ? 1 : 0);

    const buffer = new ArrayBuffer(totalBytes);
    const bytesArray = new Uint8Array(buffer);

    // Special fast path for 64-bit BigInts (common case)
    if (bitCount === 64 && completeBytes === 8 && leftoverBits === 0) {
      const byteMask = 0xffn;

      if (isLittleEndian) {
        // Little endian: LSB first
        for (let i = 0; i < 8; i++) {
          bytesArray[i] = Number((value >> BigInt(i * 8)) & byteMask);
        }
      } else {
        // Big endian: MSB first
        for (let i = 0; i < 8; i++) {
          bytesArray[i] = Number((value >> BigInt(56 - i * 8)) & byteMask);
        }
      }

      return {
        type: "bitstring",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
        hex: null,
      };
    }

    // Fast path for byte-aligned BigInts (no leftover bits)
    if (leftoverBits === 0) {
      const byteMask = 0xffn;

      if (isLittleEndian) {
        // Little endian: LSB first

        let remainingValue = value;

        for (let i = 0; i < completeBytes; i++) {
          bytesArray[i] = Number(remainingValue & byteMask);
          remainingValue = remainingValue >> 8n;
        }
      } else {
        // Big endian: MSB first

        const totalBits = BigInt(completeBytes * 8);

        for (let i = 0; i < completeBytes; i++) {
          const shift = totalBits - BigInt((i + 1) * 8);
          bytesArray[i] = Number((value >> shift) & byteMask);
        }
      }

      return {
        type: "bitstring",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
        hex: null,
      };
    }

    // Handle cases with leftover bits (not byte-aligned)
    const byteMask = 0xffn;

    if (isLittleEndian) {
      // Little endian: LSB first

      let remainingValue = value;

      // Process complete bytes
      for (let i = 0; i < completeBytes; i++) {
        bytesArray[i] = Number(remainingValue & byteMask);
        remainingValue = remainingValue >> 8n;
      }

      // Handle leftover bits - shift to the most significant bits of the byte
      if (leftoverBits > 0) {
        const leftoverMask = (1n << BigInt(leftoverBits)) - 1n;
        const shiftAmount = BigInt(8 - leftoverBits);

        bytesArray[completeBytes] = Number(
          (remainingValue & leftoverMask) << shiftAmount,
        );
      }
    } else {
      // Big endian: MSB first

      // Calculate total bits needed
      const totalBits = BigInt(completeBytes * 8 + leftoverBits);

      let remainingValue = value;

      // Process complete bytes
      for (let i = 0; i < completeBytes; i++) {
        // Calculate how many bits we still need to shift right to get the current byte
        const shift = totalBits - BigInt((i + 1) * 8);

        bytesArray[i] = Number((remainingValue >> shift) & byteMask);
      }

      // Handle leftover bits
      if (leftoverBits > 0) {
        // For leftover bits, we need to:
        // 1. Get the remaining value (last bits)
        // 2. Shift it left to align with MSB of the last byte

        const remainingBits =
          remainingValue & ((1n << BigInt(leftoverBits)) - 1n);

        bytesArray[completeBytes] = Number(
          remainingBits << BigInt(8 - leftoverBits),
        );
      }
    }

    return {
      type: "bitstring",
      text: null,
      bytes: bytesArray,
      leftoverBitCount: leftoverBits,
      hex: null,
    };
  }

  static #isLittleEndian(segment) {
    return segment.endianness === "little";
  }

  static #raiseTypeMismatchError(
    index,
    segmentType,
    expectedValueTypesStr,
    value,
  ) {
    const inspectedValue = Interpreter.inspect(value);
    const message = `construction of binary failed: segment ${index} of type '${segmentType}': expected ${expectedValueTypesStr} but got: ${inspectedValue}`;

    Interpreter.raiseArgumentError(message);
  }

  static #setFloat16(dataView, value, isLittleEndian) {
    // Handle zeros
    if (value === 0) {
      const highByte = Object.is(value, -0) ? 0x80 : 0;
      const lowByte = 0;

      if (isLittleEndian) {
        dataView.setUint8(0, lowByte);
        dataView.setUint8(1, highByte);
      } else {
        dataView.setUint8(0, highByte);
        dataView.setUint8(1, lowByte);
      }

      return;
    }

    // Extract sign and absolute value
    const absValue = Math.abs(value);
    const signByte = value < 0 ? 0x80 : 0;

    // Calculate exponent
    const exp = Math.floor(Math.log2(absValue));
    const biasedExp = exp + 15;

    // Calculate normalized fraction (remove hidden bit and scale to 10 bits)
    // Use precise multiplication to avoid rounding errors
    const significand = absValue * Math.pow(2, -exp);
    const fraction = Math.round((significand - 1) * 0x400);

    // Combine high byte: sign + 5 bits of exponent + top 2 bits of fraction
    const highByte =
      signByte | ((biasedExp & 0x1f) << 2) | ((fraction >> 8) & 0x03);

    // Low byte: bottom 8 bits of fraction
    const lowByte = fraction & 0xff;

    // Set bytes in proper order
    if (isLittleEndian) {
      dataView.setUint8(0, lowByte);
      dataView.setUint8(1, highByte);
    } else {
      dataView.setUint8(0, highByte);
      dataView.setUint8(1, lowByte);
    }
  }

  static #toIntegerFromBitstringWithLeftoverBits(
    bitstring,
    isSigned,
    isLittleEndian,
  ) {
    const bytes = bitstring.bytes;
    const byteCount = bytes.length;
    const leftoverBitCount = bitstring.leftoverBitCount;

    let result = 0n;

    // Little endian: LSB first
    // Big endian: MSB first

    // Process complete bytes first
    if (isLittleEndian) {
      for (let i = 0; i < byteCount - 1; i++) {
        result |= BigInt(bytes[i]) << BigInt(i * 8);
      }
    } else {
      for (let i = 0; i < byteCount - 1; i++) {
        result = (result << 8n) | BigInt(bytes[i]);
      }
    }

    // Handle the last byte with leftover bits
    const lastByte = bytes[byteCount - 1];
    const mask = 0xff << (8 - leftoverBitCount);
    const leftoverValue = lastByte & mask;

    // Right-shift the leftover bits to align them properly
    const shiftedValue = leftoverValue >>> (8 - leftoverBitCount);

    // Place leftover bits in the correct position
    if (isLittleEndian) {
      result |= BigInt(shiftedValue) << BigInt((byteCount - 1) * 8);
    } else {
      result = (result << BigInt(leftoverBitCount)) | BigInt(shiftedValue);
    }

    if (isSigned) {
      const bitCount = $.calculateBitCount(bitstring);
      const signBit = 1n << BigInt(bitCount - 1);

      if ((result & signBit) !== 0n) {
        result = result - (1n << BigInt(bitCount));
      }
    }

    return Type.integer(result);
  }

  static #toIntegerFromBitstringWithoutLeftoverBits(
    bitstring,
    isSigned,
    isLittleEndian,
  ) {
    const bytes = bitstring.bytes;
    const byteCount = bytes.length;

    // Use DataView for standard sizes (1, 2, 4 bytes)
    let buffer, dataView, result;

    switch (byteCount) {
      case 1:
        result = BigInt(bytes[0]);
        break;

      case 2:
        buffer = new ArrayBuffer(2);
        dataView = new DataView(buffer);

        dataView.setUint8(0, bytes[0]);
        dataView.setUint8(1, bytes[1]);

        result = isSigned
          ? BigInt(dataView.getInt16(0, isLittleEndian))
          : BigInt(dataView.getUint16(0, isLittleEndian));

        break;

      case 4:
        buffer = new ArrayBuffer(4);
        dataView = new DataView(buffer);

        dataView.setUint8(0, bytes[0]);
        dataView.setUint8(1, bytes[1]);
        dataView.setUint8(2, bytes[2]);
        dataView.setUint8(3, bytes[3]);

        result = isSigned
          ? BigInt(dataView.getInt32(0, isLittleEndian))
          : BigInt(dataView.getUint32(0, isLittleEndian));

        break;

      default:
        result = 0n;

        if (isLittleEndian) {
          for (let i = 0; i < byteCount; i++) {
            result |= BigInt(bytes[i]) << BigInt(i * 8);
          }
        } else {
          for (let i = 0; i < byteCount; i++) {
            result = (result << 8n) | BigInt(bytes[i]);
          }
        }

        if (isSigned) {
          const bitCount = $.calculateBitCount(bitstring);
          const signBit = 1n << BigInt(bitCount - 1);

          if ((result & signBit) !== 0n) {
            result = result - (1n << BigInt(bitCount));
          }
        }
    }

    return Type.integer(result);
  }

  static #validateSegmentWithBinaryType(segment, index) {
    const valueType = segment.value.type;

    if (valueType !== "bitstring" && valueType !== "string") {
      $.#raiseTypeMismatchError(index, "binary", "a binary", segment.value);
    }

    if (valueType === "bitstring" && segment.value.leftoverBitCount !== 0) {
      const inspectedValue = Interpreter.inspect(segment.value);

      Interpreter.raiseArgumentError(
        `construction of binary failed: segment ${index} of type 'binary': the size of the value ${inspectedValue} is not a multiple of the unit for the segment`,
      );
    }

    return true;
  }

  static #validateSegmentWithBitstringType(segment, index) {
    const valueType = segment.value.type;

    if (valueType === "float" || valueType === "integer") {
      $.#raiseTypeMismatchError(index, "binary", "a binary", segment.value);
    }

    if (segment.size !== null || segment.signedness !== null) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithFloatType(segment, index) {
    const valueType = segment.value.type;

    if (
      valueType !== "float" &&
      valueType !== "integer" &&
      valueType !== "variable_pattern"
    ) {
      $.#raiseTypeMismatchError(
        index,
        "float",
        "a float or an integer",
        segment.value,
      );
    }

    if (!(segment.size !== null) && segment.unit !== null) {
      Interpreter.raiseCompileError(
        "integer and float types require a size specifier if the unit specifier is given",
      );
    }

    const bitCount = $.calculateSegmentBitCount(segment);

    if (bitCount !== 16 && bitCount !== 32 && bitCount !== 64) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithIntegerType(segment, index) {
    const valueType = segment.value.type;

    if (valueType !== "integer" && valueType !== "variable_pattern") {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithUtfType(segment, index) {
    const valueType = segment.value.type;

    if (valueType === "bitstring" || valueType === "float") {
      $.#raiseTypeMismatchError(
        index,
        segment.type,
        "a non-negative integer encodable as " + segment.type,
        segment.value,
      );
    }

    if (
      segment.size !== null ||
      segment.unit !== null ||
      segment.signedness !== null
    ) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }
}

const $ = Bitstring;

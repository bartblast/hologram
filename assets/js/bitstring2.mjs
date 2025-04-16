"use strict";

import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Bitstring2 {
  static #decoder = new TextDecoder("utf-8", {fatal: true});
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
    const unit = $.resolveSegmentUnit(segment);

    return size * unit;
  }

  static calculateTextByteCount(text) {
    const blob = new Blob([text]);
    return blob.size;
  }

  static concatSegments(segments) {
    if (
      segments.every(
        (segment) => segment.type === "utf8" || segment.type === "binary",
      )
    ) {
      const segmentCount = segments.length;
      let text = "";

      for (let i = 0; i < segmentCount; i++) {
        text += segments[i].value.value;
      }

      return {type: "bitstring2", text, bytes: null, leftoverBitCount: 0};
    }

    // TODO: concat non-binary segments
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

    return {type: "bitstring2", text: null, bytes, leftoverBitCount};
  }

  static fromBytes(bytes) {
    const uint8Bytes =
      bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

    return {
      type: "bitstring2",
      text: null,
      bytes: uint8Bytes,
      leftoverBitCount: 0,
    };
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
      type: "bitstring2",
      text: null,
      bytes: new Uint8Array(buffer),
      leftoverBitCount: 0,
    };
  }

  // TODO: support utf16 and utf32 type modifiers
  static fromSegmentWithIntegerValue(segment) {
    const value = segment.value.value;

    if (segment.type === "utf8") {
      return {
        type: "bitstring2",
        text: String.fromCodePoint(Number(value)),
        bytes: null,
        leftoverBitCount: 0,
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

    // Fast path: if no size specified, use the entire string
    if (segment.size === null) {
      return {
        type: "bitstring2",
        text: valueStr,
        bytes: null,
        leftoverBitCount: 0,
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
        type: "bitstring2",
        text: valueStr,
        bytes: null,
        leftoverBitCount: 0,
      };
    }

    const sourceBytes = $.#encoder.encode(valueStr);

    // Fast path: if we need all complete bytes but no leftover bits
    if (leftoverBits === 0) {
      // We can use a subarray view of the original bytes to avoid copying
      return {
        type: "bitstring2",
        text: null,
        bytes: sourceBytes.subarray(0, completeBytes),
        leftoverBitCount: 0,
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
      type: "bitstring2",
      text: null,
      bytes,
      leftoverBitCount: leftoverBits,
    };
  }

  static fromText(text) {
    return {type: "bitstring2", text, bytes: null, leftoverBitCount: 0};
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
    if ([10, 13, 9, 11, 8, 12, 27, 127, 7].includes(codePoint)) {
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

  static resolveSegmentSize(segment) {
    if (segment?.size != null) {
      return Number(segment.size.value);
    }

    switch (segment.type) {
      case "binary":
        if (segment.value.type === "string") {
          return $.calculateTextByteCount(segment.value.value);
        }

        // bitstring2
        if (segment.value?.text != null) {
          return $.calculateTextByteCount(segment.value.text);
        }

        // bitstring2
        return segment.value.bytes.length;

      case "float":
        return 64;

      case "integer":
        return 8;

      default:
        // TODO: eventually remove this
        throw new HologramInterpreterError(
          `This case shouldn't be possible, segment = ${JSON.stringify(segment)}`,
        );
    }
  }

  static resolveSegmentUnit(segment) {
    if (segment?.unit != null && segment?.size != null) {
      return Number(segment.unit);
    }

    switch (segment.type) {
      case "binary":
        return 8;

      case "float":
      case "integer":
        return 1;

      default:
        // TODO: eventually remove this
        throw new HologramInterpreterError(
          `This case shouldn't be possible, segment = ${JSON.stringify(segment)}`,
        );
    }
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
        type: "bitstring2",
        text: null,
        bytes: bitstring.bytes.subarray(
          startByteIndex,
          startByteIndex + resultByteCount,
        ),
        leftoverBitCount: 0,
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
      type: "bitstring2",
      text: null,
      bytes: resultBytes,
      leftoverBitCount: resultLeftoverBits,
    };
  }

  // TODO: refactor and split into multiple functions for different cases
  static toInteger(bitstring, signedness, endianness) {
    $.maybeSetBytesFromText(bitstring);

    if (bitstring.bytes.length === 0) {
      return Type.integer(0n);
    }

    const bytes = bitstring.bytes;
    const byteCount = bytes.length;
    const leftoverBitCount = bitstring.leftoverBitCount;
    const isLittleEndian = endianness === "little";
    const isSigned = signedness === "signed";

    // Fast path for single byte with no leftover bits
    if (byteCount === 1 && leftoverBitCount === 0) {
      const value = bytes[0];

      return Type.integer(
        isSigned && value & 0x80 ? BigInt(value - 256) : BigInt(value),
      );
    }

    const totalBits =
      leftoverBitCount > 0
        ? (byteCount - 1) * 8 + leftoverBitCount
        : byteCount * 8;

    // Fast path for common cases (1-8 bytes, no leftover bits)
    if (leftoverBitCount === 0) {
      let result;

      // Use DataView for standard sizes (1, 2, 4 bytes)
      if (byteCount === 1) {
        result = BigInt(bytes[0]);
      } else if (byteCount === 2) {
        // Use DataView for 2 bytes
        const buffer = new ArrayBuffer(2);
        const dataView = new DataView(buffer);
        dataView.setUint8(0, bytes[0]);
        dataView.setUint8(1, bytes[1]);

        result = isSigned
          ? BigInt(dataView.getInt16(0, isLittleEndian))
          : BigInt(dataView.getUint16(0, isLittleEndian));
      } else if (byteCount === 4) {
        // Use DataView for 4 bytes
        const buffer = new ArrayBuffer(4);
        const dataView = new DataView(buffer);
        dataView.setUint8(0, bytes[0]);
        dataView.setUint8(1, bytes[1]);
        dataView.setUint8(2, bytes[2]);
        dataView.setUint8(3, bytes[3]);

        result = isSigned
          ? BigInt(dataView.getInt32(0, isLittleEndian))
          : BigInt(dataView.getUint32(0, isLittleEndian));
      } else {
        // For non-standard sizes use manual handling
        if (isLittleEndian) {
          result = 0n;
          for (let i = 0; i < byteCount; i++) {
            result |= BigInt(bytes[i]) << BigInt(i * 8);
          }
        } else {
          result = 0n;
          for (let i = 0; i < byteCount; i++) {
            result = (result << 8n) | BigInt(bytes[i]);
          }
        }

        // Handle signed values for non-standard sizes
        if (isSigned) {
          const signBit = 1n << BigInt(totalBits - 1);
          if ((result & signBit) !== 0n) {
            result = result - (1n << BigInt(totalBits));
          }
        }
      }

      return Type.integer(result);
    }

    // Handle cases with leftover bits
    let result = 0n;

    if (isLittleEndian) {
      // Little endian: LSB first
      // Process complete bytes first
      for (let i = 0; i < byteCount - 1; i++) {
        result |= BigInt(bytes[i]) << BigInt(i * 8);
      }

      // Handle the last byte with leftover bits
      const lastByte = bytes[byteCount - 1];
      const mask = 0xff << (8 - leftoverBitCount);
      const leftoverValue = lastByte & mask;

      // Place leftover bits in the correct position
      result |= BigInt(leftoverValue) << BigInt((byteCount - 1) * 8);
    } else {
      // Big endian: MSB first
      // Process complete bytes first
      for (let i = 0; i < byteCount - 1; i++) {
        result = (result << 8n) | BigInt(bytes[i]);
      }

      // Handle the last byte with leftover bits
      const lastByte = bytes[byteCount - 1];
      const mask = 0xff << (8 - leftoverBitCount);
      const leftoverValue = lastByte & mask;

      // Place leftover bits in the correct position
      result = (result << BigInt(leftoverBitCount)) | BigInt(leftoverValue);
    }

    // Handle signed values
    if (isSigned) {
      const signBit = 1n << BigInt(totalBits - 1);
      if ((result & signBit) !== 0n) {
        result = result - (1n << BigInt(totalBits));
      }
    }

    return Type.integer(result);
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

      case "bitstring2":
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
        type: "bitstring2",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
      };
    } else if (bitCount === 16 && completeBytes === 2) {
      dataView.setUint16(0, numberValue & 0xffff, isLittleEndian);

      return {
        type: "bitstring2",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
      };
    } else if (bitCount === 32 && completeBytes === 4) {
      dataView.setUint32(0, numberValue & 0xffffffff, isLittleEndian);

      return {
        type: "bitstring2",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
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
      type: "bitstring2",
      text: null,
      bytes: bytesArray,
      leftoverBitCount: leftoverBits,
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
        type: "bitstring2",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
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
        type: "bitstring2",
        text: null,
        bytes: bytesArray,
        leftoverBitCount: leftoverBits,
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
      type: "bitstring2",
      text: null,
      bytes: bytesArray,
      leftoverBitCount: leftoverBits,
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

  static #validateSegmentWithBinaryType(segment, index) {
    if (!["bitstring2", "string"].includes(segment.value.type)) {
      $.#raiseTypeMismatchError(index, "binary", "a binary", segment.value);
    }

    if (
      segment.value.type === "bitstring2" &&
      segment.value.leftoverBitCount !== 0
    ) {
      const inspectedValue = Interpreter.inspect(segment.value);

      Interpreter.raiseArgumentError(
        `construction of binary failed: segment ${index} of type 'binary': the size of the value ${inspectedValue} is not a multiple of the unit for the segment`,
      );
    }

    return true;
  }

  static #validateSegmentWithBitstringType(segment, index) {
    if (["float", "integer"].includes(segment.value.type)) {
      $.#raiseTypeMismatchError(index, "binary", "a binary", segment.value);
    }

    if (segment?.size != null || segment?.signedness != null) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithFloatType(segment, index) {
    if (
      !["float", "integer", "variable_pattern"].includes(segment.value.type)
    ) {
      $.#raiseTypeMismatchError(
        index,
        "float",
        "a float or an integer",
        segment.value,
      );
    }

    if (!(segment?.size != null) && segment?.unit != null) {
      Interpreter.raiseCompileError(
        "integer and float types require a size specifier if the unit specifier is given",
      );
    }

    const bitCount = $.calculateSegmentBitCount(segment);

    if (![64, 32, 16].includes(bitCount)) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithIntegerType(segment, index) {
    if (!["integer", "variable_pattern"].includes(segment.value.type)) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }

  static #validateSegmentWithUtfType(segment, index) {
    if (["bitstring2", "float"].includes(segment.value.type)) {
      $.#raiseTypeMismatchError(
        index,
        segment.type,
        "a non-negative integer encodable as " + segment.type,
        segment.value,
      );
    }

    if (
      segment?.size != null ||
      segment?.unit != null ||
      segment?.signedness != null
    ) {
      $.#raiseTypeMismatchError(index, "integer", "an integer", segment.value);
    }

    return true;
  }
}

const $ = Bitstring2;

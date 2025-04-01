"use strict";

import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Bitstring {
  static buildSignedBigIntFromBitArray(bitArray) {
    if (bitArray.length === 0) {
      return 0n;
    }

    const signBit = bitArray[0];

    const value = bitArray.slice(1).reduce((acc, bit, index) => {
      return acc | BigInt(bit << (bitArray.length - index - 2));
    }, 0n);

    return signBit === 1 ? -BigInt(2 ** (bitArray.length - 1)) + value : value;
  }

  static buildUnsignedBigIntFromBitArray(bitArray) {
    return bitArray.reduce((acc, bit, index) => {
      return acc | BigInt(bit << (bitArray.length - 1 - index));
    }, 0n);
  }

  // TODO: test
  static buildValueFromBitstringChunk(segment, bitArray, offset) {
    switch (segment.type) {
      case "float":
        return Bitstring.#buildFloatFromBitstringChunk(
          segment,
          bitArray,
          offset,
        );

      case "integer":
        return Bitstring.#buildIntegerFromBitstringChunk(
          segment,
          bitArray,
          offset,
        );

      case "utf8":
        return Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
          bitArray,
          offset,
        );

      default:
        throw new HologramInterpreterError(
          `building ${segment.type} value from a bitstring segment is not yet implemented in Hologram`,
        );
    }
  }

  // See: https://en.wikipedia.org/wiki/UTF-8#Encoding
  static fetchNextCodePointFromUtf8BitstringChunk(bitArray, offset) {
    const numRemainingBits = bitArray.length - offset;

    let numBytes;

    // 0xxxxxxx
    if (numRemainingBits >= 8 && bitArray[offset] === 0) {
      numBytes = 1;
    } else if (
      // 110xxxxx, 10xxxxxx
      numRemainingBits >= 16 &&
      bitArray[offset] === 1 &&
      bitArray[offset + 1] === 1 &&
      bitArray[offset + 2] === 0 &&
      bitArray[offset + 8] == 1 &&
      bitArray[offset + 9] == 0
    ) {
      numBytes = 2;
    } else if (
      //1110xxxx, 10xxxxxx, 10xxxxxx
      numRemainingBits >= 24 &&
      bitArray[offset] === 1 &&
      bitArray[offset + 1] === 1 &&
      bitArray[offset + 2] === 1 &&
      bitArray[offset + 3] === 0 &&
      bitArray[offset + 8] == 1 &&
      bitArray[offset + 9] == 0 &&
      bitArray[offset + 16] == 1 &&
      bitArray[offset + 17] == 0
    ) {
      numBytes = 3;
    } else if (
      // 11110xxx, 10xxxxxx, 10xxxxxx, 10xxxxxx
      numRemainingBits >= 32 &&
      bitArray[offset] === 1 &&
      bitArray[offset + 1] === 1 &&
      bitArray[offset + 2] === 1 &&
      bitArray[offset + 3] === 1 &&
      bitArray[offset + 4] === 0 &&
      bitArray[offset + 8] == 1 &&
      bitArray[offset + 9] == 0 &&
      bitArray[offset + 16] == 1 &&
      bitArray[offset + 17] == 0 &&
      bitArray[offset + 24] == 1 &&
      bitArray[offset + 25] == 0
    ) {
      numBytes = 4;
    } else {
      return false;
    }

    if (numBytes > 1 && offset + numBytes * 8 > bitArray.length) {
      return false;
    }

    const chunks = [];

    switch (numBytes) {
      case 1:
        chunks[0] = bitArray.slice(offset + 1, offset + 8);
        break;

      case 2:
        chunks[0] = bitArray.slice(offset + 3, offset + 8);
        chunks[1] = bitArray.slice(offset + 8 + 2, offset + 2 * 8);
        break;

      case 3:
        chunks[0] = bitArray.slice(offset + 4, offset + 8);
        chunks[1] = bitArray.slice(offset + 8 + 2, offset + 2 * 8);
        chunks[2] = bitArray.slice(offset + 2 * 8 + 2, offset + 3 * 8);
        break;

      case 4:
        chunks[0] = bitArray.slice(offset + 5, offset + 8);
        chunks[1] = bitArray.slice(offset + 8 + 2, offset + 8 + 8);
        chunks[2] = bitArray.slice(offset + 2 * 8 + 2, offset + 3 * 8);
        chunks[3] = bitArray.slice(offset + 3 * 8 + 2, offset + 4 * 8);
        break;
    }

    const codePointBitCount = chunks.reduce(
      (acc, chunk) => acc + chunk.length,
      0,
    );

    const codePointBitArray = new Uint8Array(codePointBitCount);
    let codePointOffset = 0;

    for (const chunk of chunks) {
      codePointBitArray.set(chunk, codePointOffset);
      codePointOffset += chunk.length;
    }

    const codePoint =
      Bitstring.buildUnsignedBigIntFromBitArray(codePointBitArray);

    return [Type.integer(codePoint), numBytes * 8];
  }

  static from(segments) {
    const bitArrays = segments.map((segment, index) => {
      Bitstring.validateSegment(segment, index + 1);
      return Bitstring.#buildBitArray(segment, index + 1);
    });

    return {type: "bitstring", bits: Utils.concatUint8Arrays(bitArrays)};
  }

  // Migrated to Bitstring2
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

  // Migrated to Bitstring2
  static isPrintableText(bitstring) {
    if (!Type.isBinary(bitstring)) {
      return false;
    }

    let offset = 0;

    while (offset < bitstring.bits.length) {
      const codePointInfo = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitstring.bits,
        offset,
      );

      if (!codePointInfo) {
        return false;
      }

      if (!Bitstring.validateCodePoint(codePointInfo[0].value)) {
        return false;
      }

      if (!Bitstring.isPrintableCodePoint(codePointInfo[0].value)) {
        return false;
      }

      offset += codePointInfo[1];
    }

    return true;
  }

  static isText(bitstring) {
    if (!Type.isBinary(bitstring)) {
      return false;
    }

    let offset = 0;

    while (offset < bitstring.bits.length) {
      const codePointInfo = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitstring.bits,
        offset,
      );

      if (!codePointInfo) {
        return false;
      }

      if (!Bitstring.validateCodePoint(codePointInfo[0].value)) {
        return false;
      }

      offset += codePointInfo[1];
    }

    return true;
  }

  // Using set() is much more performant than using spread operator,
  // see: https://jsben.ch/jze3P
  static merge(bitstrings) {
    const length = bitstrings.reduce(
      (acc, bitstring) => acc + bitstring.bits.length,
      0,
    );

    const bits = new Uint8Array(length);
    let offset = 0;

    for (const bitstring of bitstrings) {
      bits.set(bitstring.bits, offset);
      offset += bitstring.bits.length;
    }

    return Type.bitstring(bits);
  }

  // Migrated to Bitstring2
  static resolveSegmentSize(segment) {
    if (["float", "integer"].includes(segment.type) && segment.size !== null) {
      return segment.size.value;
    }

    switch (segment.type) {
      case "float":
        return 64n;

      case "integer":
        return 8n;

      default:
        throw new HologramInterpreterError(
          `resolving ${segment.type} segment size is not yet implemented in Hologram`,
        );
    }
  }

  // Migrated to Bitstring2
  static resolveSegmentUnit(segment) {
    if (
      ["binary", "float", "integer"].includes(segment.type) &&
      segment.unit !== null
    ) {
      return segment.unit;
    }

    switch (segment.type) {
      case "binary":
        return 8n;

      case "float":
      case "integer":
        return 1n;

      default:
        throw new HologramInterpreterError(
          `resolving ${segment.type} segment unit is not yet implemented in Hologram`,
        );
    }
  }

  static toText(bitstring) {
    const byteArray = Bitstring.#convertBitArrayToByteArray(bitstring.bits);
    const decoder = new TextDecoder("utf-8");

    return decoder.decode(byteArray);
  }

  // Migrated to Bitstring2
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

  // Migrated to Bitstring2
  static validateSegment(segment, index) {
    switch (segment.type) {
      case "binary":
        return Bitstring.#validateBinarySegment(segment, index);

      case "bitstring":
        return Bitstring.#validateBitstringSegment(segment, index);

      case "float":
        return Bitstring.#validateFloatSegment(segment, index);

      case "integer":
        return Bitstring.#validateIntegerSegment(segment, index);

      case "utf8":
      case "utf16":
      case "utf32":
        return Bitstring.#validateUtfSegment(segment, index);
    }
  }

  static #buildBitArray(segment, index) {
    switch (segment.value.type) {
      case "bitstring":
        return Bitstring.#buildBitArrayFromBitstring(segment);

      case "float":
        return Bitstring.#buildBitArrayFromFloat(segment);

      case "integer":
        return Bitstring.#buildBitArrayFromInteger(segment, index);

      case "string":
        return Bitstring.#buildBitArrayFromString(segment);
    }
  }

  static #buildBitArrayFromBitstring(segment) {
    return new Uint8Array(segment.value.bits);
  }

  static #buildBitArrayFromFloat(segment) {
    const value = segment.value.value;
    const size = Bitstring.resolveSegmentSize(segment);

    const bitArrays = Array.from(Bitstring.#getBytesFromFloat(value, size)).map(
      (byte) => Bitstring.#convertDataToBitArray(BigInt(byte), 8n, 1n),
    );

    return Utils.concatUint8Arrays(bitArrays);
  }

  static #buildBitArrayFromInteger(segment, index) {
    if (segment.type === "float") {
      const segmentWithValueCastedToFloat = {
        ...segment,
        value: Type.float(Number(segment.value.value)),
      };
      return Bitstring.#buildBitArrayFromFloat(segmentWithValueCastedToFloat);
    }

    // Max Unicode code point value is 1,114,112
    if (["utf8", "utf16", "utf32"].includes(segment.type)) {
      try {
        const str = String.fromCodePoint(Number(segment.value.value));

        const segmentWithValueCastedToString = {
          ...segment,
          value: Type.string(str),
        };

        return Bitstring.#buildBitArrayFromString(
          segmentWithValueCastedToString,
        );
      } catch {
        Bitstring.#raiseInvalidUnicodeCodePointError(segment, index);
      }
    }

    const value = segment.value.value;
    const size = Bitstring.resolveSegmentSize(segment);
    const unit = Bitstring.resolveSegmentUnit(segment);

    return Bitstring.#convertDataToBitArray(value, size, unit);
  }

  static #buildBitArrayFromString(segment) {
    const value = segment.value.value;

    const bitArrays = Array.from(
      Bitstring.#getBytesFromString(value, segment.type),
    ).map((byte) => Bitstring.#convertDataToBitArray(BigInt(byte), 8n, 1n));

    if (segment.size !== null) {
      const unit = Bitstring.resolveSegmentUnit({...segment, type: "binary"});
      const numBits = segment.size.value * unit;

      return Utils.concatUint8Arrays(bitArrays).subarray(0, Number(numBits));
    } else {
      return Utils.concatUint8Arrays(bitArrays);
    }
  }

  static #buildFloatFromBitstringChunk(segment, bitArray, offset) {
    let size = Bitstring.resolveSegmentSize(segment);

    if (![16n, 32n, 64n].includes(size)) {
      size = 64n;
    }

    if (size === 16n) {
      throw new HologramInterpreterError(
        "16-bit float bitstring segments are not yet implemented in Hologram",
      );
    }

    const unit = Bitstring.resolveSegmentUnit(segment);
    const segmentLen = Number(size * unit);

    if (offset + segmentLen > bitArray.length) {
      return false;
    }

    const chunk = bitArray.slice(offset, offset + segmentLen);
    const bytesArray = Bitstring.#convertBitArrayToByteArray(chunk);
    const dataView = new DataView(bytesArray.buffer);

    const value =
      size === 64n
        ? dataView.getFloat64(0, false)
        : dataView.getFloat32(0, false);

    return [Type.float(value), segmentLen];
  }

  static #buildIntegerFromBitstringChunk(segment, bitArray, offset) {
    const size = Bitstring.resolveSegmentSize(segment);
    const unit = Bitstring.resolveSegmentUnit(segment);
    const segmentLen = Number(size * unit);

    if (offset + segmentLen > bitArray.length) {
      return false;
    }

    const bitArrayChunk = bitArray.slice(offset, offset + segmentLen);
    let value;

    if (Bitstring.#resolveSegmentSignedness(segment) === "signed") {
      value = Bitstring.buildSignedBigIntFromBitArray(bitArrayChunk);
    } else {
      value = Bitstring.buildUnsignedBigIntFromBitArray(bitArrayChunk);
    }

    return [Type.integer(value), segmentLen];
  }

  static #convertBitArrayToByteArray(bitArray) {
    if (bitArray.length % 8 !== 0) {
      throw new HologramInterpreterError(
        `number of bits must be divisible by 8, got ${bitArray.length} bits`,
      );
    }

    const numBytes = bitArray.length / 8;
    const byteArray = new Uint8Array(numBytes);

    for (let i = 0; i < numBytes; ++i) {
      for (let j = 0; j < 8; ++j) {
        if (bitArray[i * 8 + j] === 1) {
          byteArray[i] = Bitstring.#putNumberBit(byteArray[i], 7 - j);
        }
      }
    }

    return byteArray;
  }

  static #convertDataToBitArray(data, size, unit) {
    // clamp to size number of bits
    const numBits = size * unit;
    const bitmask = 2n ** numBits - 1n;
    const clampedData = data & bitmask;

    const bitArr = [];

    for (let i = numBits; i >= 1n; --i) {
      bitArr[numBits - i] = Bitstring.#getBit(clampedData, i - 1n);
    }

    return new Uint8Array(bitArr);
  }

  static #encodeUtf16(str, endianness) {
    const byteArray = new Uint8Array(str.length * 2);
    const view = new DataView(byteArray.buffer);

    str
      .split("")
      .forEach((char, index) =>
        view.setUint16(index * 2, char.charCodeAt(0), endianness === "little"),
      );

    return byteArray;
  }

  static #getBit(value, position) {
    return (value & (1n << position)) === 0n ? 0 : 1;
  }

  static #getBytesFromFloat(float, size) {
    let floatArr;

    switch (size) {
      case 64n:
        floatArr = new Float64Array([float]);
        break;

      case 32n:
        floatArr = new Float32Array([float]);
        break;

      case 16n:
      // This case is not possible at the moment, since an error would be raised earlier.
    }

    return new Uint8Array(floatArr.buffer).reverse();
  }

  static #getBytesFromString(str, encoding) {
    switch (encoding) {
      case "binary":
      case "bitstring":
      case "utf8":
        return new TextEncoder().encode(str);

      case "utf16":
        return Bitstring.#encodeUtf16(str, "big");
    }
  }

  static #putNumberBit(value, position) {
    return value | (1 << position);
  }

  static #raiseInvalidUnicodeCodePointError(segment, index) {
    Bitstring.#raiseTypeMismatchError(
      index,
      segment.type,
      "a non-negative integer encodable as " + segment.type,
      segment.value,
    );
  }

  // Migrated to Bitstring2
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

  static #resolveSegmentSignedness(segment) {
    if (segment.signedness !== null) {
      return segment.signedness;
    }

    return "unsigned";
  }

  // Migrated to Bitstring2
  static #validateBinarySegment(segment, index) {
    if (
      segment.value.type === "bitstring" &&
      segment.value.bits.length % 8 !== 0
    ) {
      const inspectedValue = Interpreter.inspect(segment.value);

      Interpreter.raiseArgumentError(
        `construction of binary failed: segment ${index} of type 'binary': the size of the value ${inspectedValue} is not a multiple of the unit for the segment`,
      );
    }

    if (["float", "integer"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "binary",
        "a binary",
        segment.value,
      );
    }

    return true;
  }

  // Migrated to Bitstring2
  static #validateBitstringSegment(segment, index) {
    if (["float", "integer"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "binary",
        "a binary",
        segment.value,
      );
    }

    if (segment.signedness !== null || segment.size !== null) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    return true;
  }

  // Migrated to Bitstring2
  static #validateFloatSegment(segment, index) {
    if (
      !["float", "integer", "variable_pattern"].includes(segment.value.type)
    ) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "float",
        "a float or an integer",
        segment.value,
      );
    }

    if (segment.size === null && segment.unit !== null) {
      Interpreter.raiseCompileError(
        "integer and float types require a size specifier if the unit specifier is given",
      );
    }

    const size = Bitstring.resolveSegmentSize(segment);
    const unit = Bitstring.resolveSegmentUnit(segment);
    const numBits = size * unit;

    if (![16n, 32n, 64n].includes(numBits)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    if (numBits !== 64n && numBits !== 32n) {
      throw new HologramInterpreterError(
        `${numBits}-bit float bitstring segments are not yet implemented in Hologram`,
      );
    }

    return true;
  }

  // Migrated to Bitstring2
  static #validateIntegerSegment(segment, index) {
    if (!["integer", "variable_pattern"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    return true;
  }

  // Migrated to Bitstring2
  static #validateUtfSegment(segment, index) {
    if (["bitstring", "float"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        segment.type,
        "a non-negative integer encodable as " + segment.type,
        segment.value,
      );
    }

    if (
      segment.signedness !== null ||
      segment.size !== null ||
      segment.unit !== null
    ) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    return true;
  }
}

"use strict";

import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Bitstring {
  static buildBigIntFromUnsignedBitArray(bitArray) {
    const numBits = bitArray.length;
    let result = 0n;

    for (let i = 0; i < numBits; ++i) {
      if (bitArray[i] === 1) {
        result = Bitstring.#putBigIntBit(result, BigInt(numBits - 1 - i));
      }
    }

    return result;
  }

  static from(segments) {
    const bitArrays = segments.map((segment, index) => {
      Bitstring.#validateSegment(segment, index + 1);
      return Bitstring.#buildBitArray(segment, index + 1);
    });

    return {type: "bitstring", bits: Utils.concatUint8Arrays(bitArrays)};
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

    const bitArrays = Array.from(Bitstring.#getBytesFromFloat(value)).map(
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
          byteArray[i] = Bitstring.#putByteBit(byteArray[i], 7 - j);
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

  static #getBytesFromFloat(float) {
    const floatArr = new Float64Array([float]);
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

  static #putBigIntBit(value, position) {
    return value | (1n << position);
  }

  static #putByteBit(value, position) {
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

  static #validateBitstringSegment(segment, index) {
    if (["float", "integer"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "binary",
        "a binary",
        segment.value,
      );
    }

    if (segment.signedness !== null) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    return true;
  }

  static #validateFloatSegment(segment, index) {
    if (!["float", "integer"].includes(segment.value.type)) {
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
      const message = `construction of binary failed: segment ${index} of type 'float': expected one of the supported sizes 16, 32, or 64 but got: ${Number(
        numBits,
      )}`;

      Interpreter.raiseArgumentError(message);
    }

    if (numBits !== 64n) {
      throw new HologramInterpreterError(
        `${numBits}-bit float bitstring segments are not yet implemented in Hologram`,
      );
    }

    return true;
  }

  static #validateIntegerSegment(segment, index) {
    if (segment.value.type !== "integer") {
      Bitstring.#raiseTypeMismatchError(
        index,
        "integer",
        "an integer",
        segment.value,
      );
    }

    return true;
  }

  static #validateSegment(segment, index) {
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

  static #validateUtfSegment(segment, index) {
    if (["bitstring", "float"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        segment.type,
        "a non-negative integer encodable as " + segment.type,
        segment.value,
      );
    }

    if (segment.size !== null || segment.unit !== null) {
      Interpreter.raiseCompileError(
        "size and unit are not supported on utf types",
      );
    }

    if (segment.signedness !== null) {
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

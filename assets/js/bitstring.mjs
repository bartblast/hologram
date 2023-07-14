"use strict";

import Hologram from "./hologram.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Bitstring {
  static from(segments) {
    const bitArrays = segments.map((segment, index) => {
      Bitstring.#validateSegment(segment, index + 1);
      return Bitstring.#buildBitArray(segment, index + 1);
    });

    return {type: "bitstring", bits: Utils.concatUint8Arrays(bitArrays)};
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
      (byte) => Bitstring.#convertDataToBitArray(BigInt(byte), 8n, 1n)
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
          segmentWithValueCastedToString
        );
      } catch {
        Bitstring.#raiseInvalidUnicodeCodePointError(segment, index);
      }
    }

    const value = segment.value.value;
    const size = Bitstring.#resolveSizeModifierValue(segment, 8n);
    const unit = Bitstring.#resolveUnitModifierValue(segment, 1n);

    return Bitstring.#convertDataToBitArray(value, size, unit);
  }

  static #buildBitArrayFromString(segment) {
    const value = segment.value.value;

    const bitArrays = Array.from(
      Bitstring.#getBytesFromString(value, segment.type)
    ).map((byte) => Bitstring.#convertDataToBitArray(BigInt(byte), 8n, 1n));

    if (segment.size !== null) {
      const unit = Bitstring.#resolveUnitModifierValue(segment, 8n);
      const numBits = segment.size.value * unit;

      return Utils.concatUint8Arrays(bitArrays).subarray(0, Number(numBits));
    } else {
      return Utils.concatUint8Arrays(bitArrays);
    }
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
        view.setUint16(index * 2, char.charCodeAt(0), endianness === "little")
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

  static #raiseInvalidUnicodeCodePointError(segment, index) {
    Bitstring.#raiseTypeMismatchError(
      index,
      segment.type,
      "a non-negative integer encodable as " + segment.type,
      segment.value
    );
  }

  static #raiseTypeMismatchError(
    index,
    segmentType,
    expectedValueTypesStr,
    value
  ) {
    const inspectedValue = Hologram.inspect(value);
    const message = `construction of binary failed: segment ${index} of type '${segmentType}': expected ${expectedValueTypesStr} but got: ${inspectedValue}`;

    Hologram.raiseArgumentError(message);
  }

  static #resolveSizeModifierValue(segment, defaultValue) {
    if (segment.size === null) {
      return defaultValue;
    } else {
      return segment.size.value;
    }
  }

  static #resolveUnitModifierValue(segment, defaultValue) {
    if (segment.unit === null) {
      return defaultValue;
    } else {
      return segment.unit;
    }
  }

  static #validateBinarySegment(segment, index) {
    if (
      segment.value.type === "bitstring" &&
      segment.value.bits.length % 8 !== 0
    ) {
      const inspectedValue = Hologram.inspect(segment.value);

      Hologram.raiseArgumentError(
        `construction of binary failed: segment ${index} of type 'binary': the size of the value ${inspectedValue} is not a multiple of the unit for the segment`
      );
    }

    if (["float", "integer"].includes(segment.value.type)) {
      Bitstring.#raiseTypeMismatchError(
        index,
        "binary",
        "a binary",
        segment.value
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
        segment.value
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
        segment.value
      );
    }

    if (segment.size === null && segment.unit !== null) {
      Hologram.raiseCompileError(
        "integer and float types require a size specifier if the unit specifier is given"
      );
    }

    const size = Bitstring.#resolveSizeModifierValue(segment, 64n);
    const unit = Bitstring.#resolveUnitModifierValue(segment, 1n);
    const numBits = size * unit;

    if (![16n, 32n, 64n].includes(numBits)) {
      const message = `construction of binary failed: segment ${index} of type 'float': expected one of the supported sizes 16, 32, or 64 but got: ${Number(
        numBits
      )}`;
      Hologram.raiseArgumentError(message);
    }

    if (numBits !== 64n) {
      Hologram.raiseInterpreterError(
        `${numBits}-bit float bitstring segments are not yet implemented in Hologram`
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
        segment.value
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
        segment.value
      );
    }

    if (segment.size !== null || segment.unit !== null) {
      Hologram.raiseCompileError(
        "size and unit are not supported on utf types"
      );
    }

    return true;
  }
}

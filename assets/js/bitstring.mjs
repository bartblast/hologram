"use strict";

import Interpreter from "./interpreter.mjs";
import Utils from "./utils.mjs";

export default class Bitstring {
  static from(segments) {
    const bitArrays = segments.map((segment, index) => {
      Bitstring._validateSegment(segment, index + 1);
      return Bitstring._buildBitArray(segment);
    });

    // Cannot freeze array buffer views with elements
    return {type: "bitstring", bits: Utils.concatUint8Arrays(bitArrays)};
  }

  // private
  static _buildBitArray(segment) {
    switch (segment.value.type) {
      case "bitstring":
        return Bitstring._buildBitArrayFromBitstring(segment);

      case "float":
        return Bitstring._buildBitArrayFromFloat(segment);

      case "integer":
        return Bitstring._buildBitArrayFromInteger(segment);

      case "string":
        return Bitstring._buildBitArrayFromString(segment);
    }
  }

  // private
  static _buildBitArrayFromBitstring(segment) {
    return new Uint8Array(segment.value.bits);
  }

  // private
  static _buildBitArrayFromFloat(segment) {
    const value = segment.value.value;

    const bitArrays = Array.from(Bitstring._getBytesFromFloat(value)).map(
      (byte) => Bitstring._convertDataToBitArray(BigInt(byte), 8n, 1n)
    );

    return Utils.concatUint8Arrays(bitArrays);
  }

  // private
  static _buildBitArrayFromInteger(segment) {
    const value = segment.value.value;
    const size = Bitstring._resolveSizeModifierValue(segment, 8n);
    const unit = Bitstring._resolveUnitModifierValue(segment, 1n);

    return Bitstring._convertDataToBitArray(value, size, unit);
  }

  // private
  static _buildBitArrayFromString(segment) {
    const value = segment.value.value;

    const bitArrays = Array.from(Bitstring._getBytesFromString(value)).map(
      (byte) => Bitstring._convertDataToBitArray(BigInt(byte), 8n, 1n)
    );

    if (segment.size !== null) {
      const unit = Bitstring._resolveUnitModifierValue(segment, 8n);
      const numBits = segment.size.value * unit;

      return Utils.concatUint8Arrays(bitArrays).subarray(0, Number(numBits));
    } else {
      return Utils.concatUint8Arrays(bitArrays);
    }
  }

  // private
  static _convertDataToBitArray(data, size, unit) {
    // clamp to size number of bits
    const numBits = size * unit;
    const bitmask = 2n ** numBits - 1n;
    const clampedData = data & bitmask;

    const bitArr = [];

    for (let i = numBits; i >= 1n; --i) {
      bitArr[numBits - i] = Bitstring._getBit(clampedData, i - 1n);
    }

    return new Uint8Array(bitArr);
  }

  // private
  static _getBit(value, position) {
    return (value & (1n << position)) === 0n ? 0 : 1;
  }

  // private
  static _getBytesFromFloat(float) {
    const floatArr = new Float64Array([float]);
    return new Uint8Array(floatArr.buffer).reverse();
  }

  // private
  static _getBytesFromString(string) {
    return new TextEncoder().encode(string);
  }

  // private
  static _raiseInvalidValueTypeError(index, value, type) {
    const inspectedValue = Interpreter.inspect(value);
    const indefiniteArticle = Utils.indefiniteArticle(type);
    const message = `construction of binary failed: segment ${index} of type '${type}': expected ${indefiniteArticle} ${type} but got: ${inspectedValue}`;
    Interpreter.raiseError("ArgumentError", message);
  }

  // private
  static _resolveSizeModifierValue(segment, defaultValue) {
    if (segment.size === null) {
      return defaultValue;
    } else {
      return segment.size.value;
    }
  }

  // private
  static _resolveUnitModifierValue(segment, defaultValue) {
    if (segment.unit === null) {
      return defaultValue;
    } else {
      return segment.unit;
    }
  }

  // private
  static _validateBinarySegment(segment, index) {
    if (
      segment.value.type === "bitstring" &&
      segment.value.bits.length % 8 !== 0
    ) {
      const inspectedValue = Interpreter.inspect(segment.value);

      Interpreter.raiseError(
        "ArgumentError",
        `construction of binary failed: segment ${index} of type 'binary': the size of the value ${inspectedValue} is not a multiple of the unit for the segment`
      );
    }

    return true;
  }

  // private
  static _validateFloatSegment(segment, index) {
    if (segment.value.type !== "float") {
      const inspectedValue = Interpreter.inspect(segment.value);

      Interpreter.raiseError(
        "ArgumentError",
        `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: ${inspectedValue}`
      );
    }

    if (segment.size === null && segment.unit !== null) {
      Interpreter.raiseError(
        "CompileError",
        "integer and float types require a size specifier if the unit specifier is given"
      );
    }

    const size = Bitstring._resolveSizeModifierValue(segment, 64n);
    const unit = Bitstring._resolveUnitModifierValue(segment, 1n);
    const numBits = size * unit;

    if (![16n, 32n, 64n].includes(numBits)) {
      const message = `construction of binary failed: segment ${index} of type 'float': expected one of the supported sizes 16, 32, or 64 but got: ${Number(
        numBits
      )}`;
      Interpreter.raiseError("ArgumentError", message);
    }

    if (numBits !== 64n) {
      Interpreter.raiseNotYetImplementedError(
        `${numBits}-bit float bitstring segments are not yet implemented in Hologram`
      );
    }

    return true;
  }

  // private
  static _validateIntegerSegment(segment, index) {
    if (segment.value.type !== "integer") {
      Bitstring._raiseInvalidValueTypeError(index, segment.value, "integer");
    }

    return true;
  }

  // private
  static _validateSegment(segment, index) {
    switch (segment.type) {
      case "binary":
        return Bitstring._validateBinarySegment(segment, index);

      case "bitstring":
        return true;

      case "float":
        return Bitstring._validateFloatSegment(segment, index);

      case "integer":
        return Bitstring._validateIntegerSegment(segment, index);

      case "utf8":
        return Bitstring._validateUtf8Segment(segment);
    }
  }

  // private
  static _validateUtf8Segment(segment) {
    if (segment.size !== null || segment.unit !== null) {
      Interpreter.raiseError(
        "CompileError",
        "size and unit are not supported on utf types"
      );
    }

    return true;
  }
}

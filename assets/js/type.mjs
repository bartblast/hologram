"use strict";

import Interpreter from "./interpreter.mjs";
import Utils from "./utils.mjs";

export default class Type {
  static atom(value) {
    return Utils.freeze({type: "atom", value: value});
  }

  static bitstring(data) {
    let bits;

    if (data.length > 0 && typeof data[0] == "object") {
      const bitArrays = data.map((segment, index) =>
        Type._buildBitstringSegmentBitArray(segment, index + 1)
      );

      bits = Utils.concatUint8Arrays(bitArrays);
    } else {
      bits = new Uint8Array(data);
    }

    // Cannot freeze array buffer views with elements
    return {type: "bitstring", bits: bits};
  }

  static bitstringSegment(value, modifiers = {}) {
    const type = Type._getOption(modifiers, "type");
    const size = Type._getOption(modifiers, "size");
    const unit = Type._getOption(modifiers, "unit");
    const signedness = Type._getOption(modifiers, "signedness");
    const endianness = Type._getOption(modifiers, "endianness");

    return {value, type, size, unit, signedness, endianness};
  }

  static boolean(value) {
    return Type.atom(value.toString());
  }

  static consPattern(head, tail) {
    return Utils.freeze({type: "cons_pattern", head: head, tail: tail});
  }

  static encodeMapKey(boxed) {
    switch (boxed.type) {
      case "atom":
      case "float":
      case "integer":
      case "string":
        return Type._encodePrimitiveTypeMapKey(boxed);

      case "bitstring":
        return Type._encodeBitstringTypeMapKey(boxed);

      case "list":
      case "tuple":
        return Type._encodeEnumTypeMapKey(boxed);

      case "map":
        return Type._encodeMapTypeMapKey(boxed);
    }
  }

  static float(value) {
    return Utils.freeze({type: "float", value: value});
  }

  static integer(value) {
    if (typeof value !== "bigint") {
      value = BigInt(value);
    }

    return Utils.freeze({type: "integer", value: value});
  }

  static isAtom(boxed) {
    return boxed.type === "atom";
  }

  static isConsPattern(boxed) {
    return boxed.type === "cons_pattern";
  }

  static isFalse(boxed) {
    return Type.isAtom(boxed) && boxed.value === "false";
  }

  static isFloat(boxed) {
    return boxed.type === "float";
  }

  static isInteger(boxed) {
    return boxed.type === "integer";
  }

  static isList(boxed) {
    return boxed.type === "list";
  }

  static isMap(boxed) {
    return boxed.type === "map";
  }

  static isNumber(boxed) {
    return Type.isInteger(boxed) || Type.isFloat(boxed);
  }

  static isTrue(boxed) {
    return Type.isAtom(boxed) && boxed.value === "true";
  }

  static isVariablePattern(boxed) {
    return boxed.type === "variable_pattern";
  }

  static list(data) {
    return Utils.freeze({type: "list", data: data});
  }

  static map(data) {
    const hashTableWithMetadata = data.reduce((acc, [boxedKey, boxedValue]) => {
      acc[Type.encodeMapKey(boxedKey)] = [boxedKey, boxedValue];
      return acc;
    }, {});

    return Utils.freeze({type: "map", data: hashTableWithMetadata});
  }

  static string(value) {
    return Utils.freeze({type: "string", value: value});
  }

  static tuple(data) {
    return Utils.freeze({type: "tuple", data: data});
  }

  static variablePattern(name) {
    return Utils.freeze({type: "variable_pattern", name: name});
  }

  // private
  static _buildBitArrayFromBitstring(segment) {
    return new Uint8Array(segment.value.bits);
  }

  // private
  static _buildBitArrayFromFloat(segment, index) {
    if (segment.size === null && segment.unit !== null) {
      Interpreter.raiseError(
        "CompileError",
        "integer and float types require a size specifier if the unit specifier is given"
      );
    }

    const size = Type._resolveSizeModifierValue(segment, 64n);
    const unit = Type._resolveUnitModifierValue(segment, 1n);
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

    const value = segment.value.value;

    const bitArrays = Array.from(Type._getBytesFromFloat(value)).map((byte) =>
      Type._convertDataToBitArray(BigInt(byte), 8n, 1n)
    );

    return Utils.concatUint8Arrays(bitArrays);
  }

  // private
  static _buildBitArrayFromInteger(segment) {
    const value = segment.value.value;
    const size = Type._resolveSizeModifierValue(segment, 8n);
    const unit = Type._resolveUnitModifierValue(segment, 1n);

    return Type._convertDataToBitArray(value, size, unit);
  }

  // private
  static _buildBitArrayFromString(segment) {
    const {type} = segment;

    if (["utf8", "utf16", "utf32"].includes(type)) {
      if (segment.size !== null || segment.unit !== null) {
        Interpreter.raiseError(
          "CompileError",
          "size and unit are not supported on utf types"
        );
      }
    }

    if (["utf16", "utf32"].includes(type)) {
      Interpreter.raiseNotYetImplementedError(
        `${type} bitstring segment type is not yet implemented in Hologram`
      );
    }

    const value = segment.value.value;

    const bitArrays = Array.from(Type._getBytesFromString(value)).map((byte) =>
      Type._convertDataToBitArray(BigInt(byte), 8n, 1n)
    );

    if (segment.size !== null) {
      const unit = Type._resolveUnitModifierValue(segment, 8n);
      const numBits = segment.size.value * unit;

      return Utils.concatUint8Arrays(bitArrays).subarray(0, Number(numBits));
    } else {
      return Utils.concatUint8Arrays(bitArrays);
    }
  }

  // private
  static _buildBitstringSegmentBitArray(segment, index) {
    segment = Type._resolveBistringSegmentType(segment);
    Type._validateBitstringSegmentType(segment, index);

    switch (segment.type) {
      case "binary":
      case "utf8":
      case "utf16":
      case "utf32":
        return Type._buildBitArrayFromString(segment);

      case "bitstring":
        return Type._buildBitArrayFromBitstring(segment);

      case "float":
        return Type._buildBitArrayFromFloat(segment, index);

      case "integer":
        return Type._buildBitArrayFromInteger(segment);
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
      bitArr[numBits - i] = Type._getBit(clampedData, i - 1n);
    }

    return new Uint8Array(bitArr);
  }

  // private
  static _encodeBitstringTypeMapKey(boxed) {
    return "bitstring(" + boxed.bits.join("") + ")";
  }

  // private
  static _encodeEnumTypeMapKey(boxed) {
    const itemsStr = boxed.data
      .map((item) => Type.encodeMapKey(item))
      .join(",");

    return boxed.type + "(" + itemsStr + ")";
  }

  // private
  static _encodeMapTypeMapKey(boxed) {
    const itemsStr = Object.keys(boxed.data)
      .sort()
      .map((key) => key + ":" + Type.encodeMapKey(boxed.data[key][1]))
      .join(",");

    return "map(" + itemsStr + ")";
  }

  // private
  static _encodePrimitiveTypeMapKey(boxed) {
    return `${boxed.type}(${boxed.value})`;
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
  static _getOption(options, key) {
    return typeof options[key] !== "undefined" ? options[key] : null;
  }

  // private
  static _resolveBistringSegmentType(segment) {
    const {value, type} = segment;

    if (type === null) {
      if (["bitstring", "integer", "float"].includes(value.type)) {
        segment.type = value.type;
      } else if (value.type === "string") {
        segment.type = "utf8";
      } else {
        segment.type = "integer";
      }
    }

    return segment;
  }

  // private
  static _validateBitstringSegmentType(segment, index) {
    const {value, type} = segment;

    if (value.type === type) {
      return true;
    } else if (
      value.type === "string" &&
      ["binary", "utf8", "utf16", "utf32"].includes(type)
    ) {
      return true;
    }

    Type._raiseInvalidBitstringSegmentType(index, value, type);
  }

  static _raiseInvalidBitstringSegmentType(index, value, type) {
    const inspectedValue = Interpreter.inspect(value);
    const indefiniteArticle = Utils.indefiniteArticle(type);
    const message = `construction of binary failed: segment ${index} of type '${type}': expected ${indefiniteArticle} ${type} but got: ${inspectedValue}`;
    Interpreter.raiseError("ArgumentError", message);
  }

  static _resolveSizeModifierValue(segment, defaultValue) {
    if (segment.size === null) {
      return defaultValue;
    } else {
      return segment.size.value;
    }
  }

  static _resolveUnitModifierValue(segment, defaultValue) {
    if (segment.unit === null) {
      return defaultValue;
    } else {
      return segment.unit;
    }
  }
}

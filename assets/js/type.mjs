"use strict";

import Bitstring from "./bitstring.mjs";
import Sequence from "./sequence.mjs";
import Utils from "./utils.mjs";

export default class Type {
  static anonymousFunction(vars, closureBuilder) {
    return Utils.freeze({
      type: "anonymous_function",
      closure: closureBuilder(Utils.clone(vars)),
      uniqueId: Sequence.next(),
    });
  }

  static atom(value) {
    return Utils.freeze({type: "atom", value: value});
  }

  static bitstring(data) {
    if (typeof data === "string") {
      return Type.bitstring([
        Type.bitstringSegment(Type.string(data), {type: "utf8"}),
      ]);
    } else if (data.length > 0 && typeof data[0] === "object") {
      return Bitstring.from(data);
    } else {
      // Cannot freeze array buffer views with elements
      return {type: "bitstring", bits: new Uint8Array(data)};
    }
  }

  static bitstringSegment(value, modifiers = {}) {
    const type = Type._getOption(modifiers, "type");

    if (type === null) {
      throw new Error("Bitstring segment type modifier is not specified");
    }

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
      case "anonymous_function":
        return Type._encodeAnonymousFunctionTypeMapKey(boxed);

      case "atom":
      case "float":
      case "integer":
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

  static isTuple(boxed) {
    return boxed.type === "tuple";
  }

  static isVariablePattern(boxed) {
    return boxed.type === "variable_pattern";
  }

  static list(data) {
    // Do not freeze lists, since they may contain bitstring items which can't be frozen.
    // TODO: freeze again once bitstrings are implemented as bigints.
    return {type: "list", data: data};
  }

  static map(data) {
    const hashTableWithMetadata = data.reduce((acc, [boxedKey, boxedValue]) => {
      acc[Type.encodeMapKey(boxedKey)] = [boxedKey, boxedValue];
      return acc;
    }, {});

    return Utils.freeze({type: "map", data: hashTableWithMetadata});
  }

  static matchPlaceholder() {
    return Utils.freeze({type: "match_placeholder"});
  }

  static string(value) {
    return Utils.freeze({type: "string", value: value});
  }

  static tuple(data) {
    // Do not freeze tuples, since they may contain bitstring items which can't be frozen.
    // TODO: freeze again once bitstrings are implemented as bigints.
    return {type: "tuple", data: data};
  }

  static variablePattern(name) {
    return Utils.freeze({type: "variable_pattern", name: name});
  }

  // private
  static _encodeAnonymousFunctionTypeMapKey(boxed) {
    return "anonymous_function(" + boxed.uniqueId + ")";
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
  static _getOption(options, key) {
    return typeof options[key] !== "undefined" ? options[key] : null;
  }
}

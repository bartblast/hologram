"use strict";

import Bitstring from "./bitstring.mjs";
import Sequence from "./sequence.mjs";

export default class Type {
  static alias(aliasStr) {
    return Type.atom(`Elixir.${aliasStr}`);
  }

  static anonymousFunction(arity, clauses, vars) {
    return {
      type: "anonymous_function",
      arity: arity,
      clauses: clauses,
      vars: Hologram.cloneVars(vars),
      uniqueId: Sequence.next(),
    };
  }

  static atom(value) {
    return {type: "atom", value: value};
  }

  static bitstring(data) {
    if (typeof data === "string") {
      return Type.bitstring([
        Type.bitstringSegment(Type.string(data), {type: "utf8"}),
      ]);
    } else if (data.length > 0 && typeof data[0] === "object") {
      return Bitstring.from(data);
    } else {
      return {type: "bitstring", bits: new Uint8Array(data)};
    }
  }

  static bitstringPattern(segments) {
    return {type: "bitstring_pattern", segments: segments};
  }

  static bitstringSegment(value, modifiers = {}) {
    const type = Type.#getOption(modifiers, "type");

    // TODO: is this needed?
    if (type === null) {
      Hologram.raiseInterpreterError(
        "bitstring segment type modifier is not specified",
      );
    }

    const size = Type.#getOption(modifiers, "size");
    const unit = Type.#getOption(modifiers, "unit");
    const signedness = Type.#getOption(modifiers, "signedness");
    const endianness = Type.#getOption(modifiers, "endianness");

    return {value, type, size, unit, signedness, endianness};
  }

  static boolean(value) {
    return Type.atom(value.toString());
  }

  static consPattern(head, tail) {
    return {type: "cons_pattern", head: head, tail: tail};
  }

  static encodeMapKey(boxed) {
    switch (boxed.type) {
      case "anonymous_function":
        return Type.#encodeAnonymousFunctionTypeMapKey(boxed);

      case "atom":
      case "float":
      case "integer":
        return Type.#encodePrimitiveTypeMapKey(boxed);

      case "bitstring":
        return Type.#encodeBitstringTypeMapKey(boxed);

      case "list":
      case "tuple":
        return Type.#encodeEnumTypeMapKey(boxed);

      case "map":
        return Type.#encodeMapTypeMapKey(boxed);
    }
  }

  static errorStruct(aliasStr, message) {
    const data = [
      [Type.atom("__exception__"), Type.boolean(true)],
      [Type.atom("message"), Type.bitstring(message)],
    ];

    return Type.struct(aliasStr, data);
  }

  static float(value) {
    return {type: "float", value: value};
  }

  static improperList(data) {
    if (data.length < 2) {
      Hologram.raiseInterpreterError(
        "improper list must have at least 2 items, received " +
          Hologram.serialize(data),
      );
    }

    return {type: "list", data: data, isProper: false};
  }

  static integer(value) {
    if (typeof value !== "bigint") {
      value = BigInt(value);
    }

    return {type: "integer", value: value};
  }

  static isAtom(boxed) {
    return boxed.type === "atom";
  }

  static isBitstringPattern(boxed) {
    return boxed.type === "bitstring_pattern";
  }

  static isBoolean(boxed) {
    return (
      boxed.type === "atom" &&
      (boxed.value === "false" || boxed.value === "true")
    );
  }

  static isConsPattern(boxed) {
    return boxed.type === "cons_pattern";
  }

  static isFalse(boxed) {
    return Type.isAtom(boxed) && boxed.value === "false";
  }

  static isFalsy(boxed) {
    return Type.isFalse(boxed) || Type.isNil(boxed);
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

  static isMatchPlaceholder(boxed) {
    return boxed.type === "match_placeholder";
  }

  static isNil(boxed) {
    return boxed.type === "atom" && boxed.value === "nil";
  }

  static isNumber(boxed) {
    return Type.isInteger(boxed) || Type.isFloat(boxed);
  }

  static isProperList(boxedValue) {
    return Type.isList(boxedValue) && boxedValue.isProper === true;
  }

  static isTrue(boxed) {
    return Type.isAtom(boxed) && boxed.value === "true";
  }

  static isTruthy(boxed) {
    return !Type.isFalsy(boxed);
  }

  static isTuple(boxed) {
    return boxed.type === "tuple";
  }

  static isVariablePattern(boxed) {
    return boxed.type === "variable_pattern";
  }

  static list(data) {
    return {type: "list", data: data, isProper: true};
  }

  static map(data) {
    const hashTableWithMetadata = data.reduce((acc, [boxedKey, boxedValue]) => {
      acc[Type.encodeMapKey(boxedKey)] = [boxedKey, boxedValue];
      return acc;
    }, {});

    return {type: "map", data: hashTableWithMetadata};
  }

  static matchPlaceholder() {
    return {type: "match_placeholder"};
  }

  static nil() {
    return Type.atom("nil");
  }

  static maybeNormalizeNumberTerms(term1, term2) {
    const type =
      Type.isFloat(term1) || Type.isFloat(term2) ? "float" : "integer";

    let value1, value2;

    if (type === "float" && Type.isInteger(term1)) {
      value1 = Type.float(Number(term1.value));
    } else {
      value1 = term1;
    }

    if (type === "float" && Type.isInteger(term2)) {
      value2 = Type.float(Number(term2.value));
    } else {
      value2 = term2;
    }

    return [type, value1, value2];
  }

  static string(value) {
    return {type: "string", value: value};
  }

  static struct(aliasStr, data) {
    const key = Type.atom("__struct__");
    const value = Type.alias(aliasStr);

    return Type.map(data.concat([[key, value]]));
  }

  static tuple(data) {
    return {type: "tuple", data: data};
  }

  static variablePattern(name) {
    return {type: "variable_pattern", name: name};
  }

  static #encodeAnonymousFunctionTypeMapKey(boxed) {
    return "anonymous_function(" + boxed.uniqueId + ")";
  }

  static #encodeBitstringTypeMapKey(boxed) {
    return "bitstring(" + boxed.bits.join("") + ")";
  }

  static #encodeEnumTypeMapKey(boxed) {
    const itemsStr = boxed.data
      .map((item) => Type.encodeMapKey(item))
      .join(",");

    return boxed.type + "(" + itemsStr + ")";
  }

  static #encodeMapTypeMapKey(boxed) {
    const itemsStr = Object.keys(boxed.data)
      .sort()
      .map((key) => key + ":" + Type.encodeMapKey(boxed.data[key][1]))
      .join(",");

    return "map(" + itemsStr + ")";
  }

  static #encodePrimitiveTypeMapKey(boxed) {
    return `${boxed.type}(${boxed.value})`;
  }

  static #getOption(options, key) {
    return typeof options[key] !== "undefined" ? options[key] : null;
  }
}

"use strict";

import Bitstring2 from "./bitstring2.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(serialized, isVersioned = true) {
    let version = null;

    const deserialized = JSON.parse(serialized, (_key, value) => {
      if (version === null) {
        version = isVersioned ? parseInt(value) : Serializer.CURRENT_VERSION;
      }

      if (typeof value === "string") {
        const result = $.#maybeDeserializeStringTerm(value, version);

        if (result !== null) {
          return result;
        }
      }

      const result = $.#maybeDeserializeObjectTerm(value, version);

      if (result !== null) {
        return result;
      }

      return value;
    });

    return isVersioned ? deserialized[1] : deserialized;
  }

  static #deserializeBitstring(serialized) {
    const parts = serialized.split(":");
    const hex = parts[1];
    const hexLength = hex.length;
    const bytes = new Uint8Array(hexLength >> 1);

    // Use separate j index variable to avoid division in each iteration
    for (let i = 0, j = 0; i < hexLength; i += 2, j++) {
      bytes[j] = parseInt(hex.slice(i, i + 2), 16);
    }

    const bitstring = Bitstring2.fromBytes(bytes);

    if (parts.length === 3) {
      bitstring.leftoverBitCount = parseInt(parts[2]);
    }

    return bitstring;
  }

  static #maybeDeserializeObjectTerm(value, version) {
    const boxedValueType = value?.type;

    if (boxedValueType === "map") {
      return Type.map(value.data);
    }

    if (version === 1) {
      if (boxedValueType === "bitstring") {
        return Type.bitstring(value.bits);
      }
    }

    return null;
  }

  static #maybeDeserializeStringTerm(value, version) {
    if (version >= 2) {
      if (value.startsWith("a:")) {
        return Type.atom(value.slice(2));
      }

      if (value.startsWith("b:")) {
        return $.#deserializeBitstring(value);
      }

      if (value === "b") {
        return Type.bitstring2("");
      }

      if (value.startsWith("f:")) {
        return Type.float(Number(value.slice(2)));
      }

      if (value.startsWith("i:")) {
        return Type.integer(BigInt(value.slice(2)));
      }
    }

    if (value.startsWith("__atom__:")) {
      return Type.atom(value.slice(9));
    }

    if (value.startsWith("__bigint__:")) {
      return BigInt(value.slice(11));
    }

    if (value.startsWith("__binary__:")) {
      return Type.bitstring(value.slice(11));
    }

    if (value.startsWith("__float__:")) {
      return Type.float(Number(value.slice(10)));
    }

    if (value.startsWith("__function__:")) {
      return Interpreter.evaluateJavaScriptExpression(value.slice(13));
    }

    if (value.startsWith("__integer__:")) {
      return Type.integer(BigInt(value.slice(12)));
    }

    return null;
  }
}

const $ = Deserializer;

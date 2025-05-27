"use strict";

import Bitstring2 from "./bitstring2.mjs";
// import Interpreter from "./interpreter.mjs";
// import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(serialized) {
    let version = null;

    return JSON.parse(serialized, (_key, value) => {
      if (version === null) {
        version = parseInt(value);
      }

      if (typeof value === "string") {
        return $.#maybeDeserializeStringTerm(value, version);
      }

      return $.#maybeDeserializeObjectTerm(value, version);

      //       const result = $.#maybeDeserializeObjectTerm(value, version);
      //       if (result !== null) {
      //         return result;
      //       }
      return value;
    })[1];
  }

  static #deserializeBitstring(serialized) {
    if (serialized === "b") {
      return Type.bitstring2("");
    }

    const hex = serialized.slice(2);
    const hexLength = hex.length;
    const bytes = new Uint8Array(hexLength >> 1);

    // Use separate j index variable to avoid division in each iteration
    for (let i = 0, j = 0; i < hexLength; i += 2, j++) {
      bytes[j] = parseInt(hex.slice(i, i + 2), 16);
    }

    const bitstring = Bitstring2.fromBytes(bytes);
    bitstring.leftoverBitCount = serialized[1];

    return bitstring;
  }

  static #maybeDeserializeObjectTerm(obj, version) {
    //     if (version >= 2) {
    //       const boxedValueType = value?.t;
    //       if (boxedValueType === "m") {
    //         return Type.map(value.d);
    //       }
    //       if (boxedValueType === "t") {
    //         return Type.tuple(value.d);
    //       }
    //     }

    if (version === 1) {
      const boxedValueType = obj?.type;

      //       if (boxedValueType === "map") {
      //         return Type.map(value.data);
      //       }

      if (boxedValueType === "bitstring") {
        return Type.bitstring2(obj.bits);
      }
    }

    // return null;
    return obj;
  }

  static #maybeDeserializeStringTerm(serialized, version) {
    if (version >= 2) {
      const typeCode = serialized[0];
      const data = serialized.slice(1);

      switch (typeCode) {
        case "a":
          return Type.atom(data);

        case "b":
          return $.#deserializeBitstring(serialized);

        case "f":
          return Type.float(Number(data));

        case "i":
          return Type.integer(BigInt(data));

        case "s":
          return data;
      }
    }

    if (serialized.startsWith("__atom__:")) {
      return Type.atom(serialized.slice(9));
    }

    if (serialized.startsWith("__binary__:")) {
      return Type.bitstring2(serialized.slice(11));
    }

    if (serialized.startsWith("__float__:")) {
      return Type.float(Number(serialized.slice(10)));
    }

    if (serialized.startsWith("__integer__:")) {
      return Type.integer(BigInt(serialized.slice(12)));
    }

    return serialized;
    //     if (value.startsWith("__bigint__:")) {
    //       return BigInt(value.slice(11));
    //     }
    //     if (value.startsWith("__function__:")) {
    //       return Interpreter.evaluateJavaScriptExpression(value.slice(13));
    //     }
  }
}

const $ = Deserializer;

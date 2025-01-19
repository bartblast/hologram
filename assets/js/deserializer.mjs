"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(serialized, isVersioned = true) {
    const deserialized = JSON.parse(serialized, (_key, value) => {
      if (typeof value === "string") {
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
      }

      if (value?.type === "bitstring") {
        return Type.bitstring(value.bits);
      }

      if (value?.type === "map") {
        return Type.map(value.data);
      }

      return value;
    });

    return isVersioned ? deserialized[1] : deserialized;
  }
}

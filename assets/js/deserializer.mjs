"use strict";

import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(serialized, isVersioned = true) {
    const deserialized = JSON.parse(serialized, (_key, value) => {
      if (typeof value === "string") {
        if (value.startsWith("__atom__:")) {
          return Type.atom(value.slice(9));
        }

        if (value.startsWith("__binary__:")) {
          return Type.bitstring(value.slice(11));
        }
      }

      if (value?.type === "bitstring") {
        return Type.bitstring(value.bits);
      }

      return value;
    });

    return isVersioned ? deserialized[1] : deserialized;
  }
}

const $ = Deserializer;

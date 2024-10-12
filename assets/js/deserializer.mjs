"use strict";

import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(data) {
    return JSON.parse(data, (_key, value) => {
      if (typeof value === "string") {
        if (value.startsWith("__integer__:")) {
          return Type.integer(BigInt(value.slice(12)));
        }

        if (value.startsWith("__binary__:")) {
          return Type.bitstring(value.slice(11));
        }
      }

      return value;
    });
  }
}

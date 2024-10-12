"use strict";

import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(data) {
    return JSON.parse(data, (_key, value) => {
      if (typeof value === "string" && value.startsWith("__integer__:")) {
        return Type.integer(BigInt(value.slice(12)));
      }

      return value;
    });
  }
}

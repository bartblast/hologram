"use strict";

import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(data) {
    return typeof data === "string" ? $.#parseJson(data) : data;
  }

  static #parseJson(json) {
    return JSON.parse(json, (_key, value) => {
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

const $ = Deserializer;

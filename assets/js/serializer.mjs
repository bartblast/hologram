"use strict";

import Bitstring from "./bitstring.mjs";
import Type from "./type.mjs";

export default class Serializer {
  static serialize(term) {
    const serialized = JSON.stringify(term, (_key, value) => {
      if (value?.type === "atom") {
        return `__atom__:${value.value}`;
      }

      if (value?.type === "bitstring") {
        if (Type.isBinary(value)) {
          return `__binary__:${Bitstring.toText(value)}`;
        }

        return {...value, bits: Array.from(value.bits)};
      }

      if (value?.type === "float") {
        return `__float__:${value.value.toString()}`;
      }

      if (value?.type === "integer") {
        return `__integer__:${value.value.toString()}`;
      }

      if (value?.type === "map") {
        return {...value, data: Object.values(value.data)};
      }

      if (typeof value === "bigint") {
        return `__bigint__:${value.toString()}`;
      }

      return value;
    });

    if (
      !serialized.startsWith('"') &&
      !serialized.startsWith("{") &&
      !serialized.startsWith("[")
    ) {
      // [version, data]
      return `[1,"${serialized}"]`;
    }

    // [version, data]
    return `[1,${serialized}]`;
  }
}

const $ = Serializer;

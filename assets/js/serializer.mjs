"use strict";

export default class Serializer {
  static serialize(term) {
    const serialized = JSON.stringify(term, (_key, value) => {
      if (typeof value === "bigint") {
        return `__bigint__:${value.toString()}`;
      }

      return value;
    });

    if (!serialized.startsWith("{") && !serialized.startsWith("[")) {
      return `"${serialized}"`;
    }

    return serialized;
  }
}

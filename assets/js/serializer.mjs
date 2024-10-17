"use strict";

export default class Serializer {
  static serialize(term) {
    const serialized = JSON.stringify(term, (_key, value) => {
      if (value?.type === "atom") {
        return `__atom__:${value.value}`;
      }

      if (value?.type === "integer") {
        return `__integer__:${value.value.toString()}`;
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
      return `"${serialized}"`;
    }

    return serialized;
  }
}

const $ = Serializer;

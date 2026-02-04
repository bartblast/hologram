"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";

/*
Serializer Format Changelog

Release 0.7.0: switched to version 3.
*/

export default class Serializer {
  static CURRENT_VERSION = 3;

  // Can't use control characters in 0x00-0x1F (0-31) range
  // because they are escaped in JSON and result in multi-byte delimiter.
  // Can't use characters above 0x7F (128) because they mess up transmission encoding.
  // Using \x7F (DEL character) which is practically unused.
  static DELIMITER = "\x7F";

  static serialize(term, destination = "server") {
    const serialized = JSON.stringify(term, (key, value) => {
      const boxedTermType = value?.type;

      switch (boxedTermType) {
        case "anonymous_function":
          return $.#serializeBoxedFunction(value, destination);

        case "atom":
          return `a${value.value}`;

        case "bitstring":
          return Bitstring.serialize(value);

        case "float":
          return `f${value.value}`;

        case "integer":
          return `i${value.value}`;

        case "list":
          return {t: "l", d: value.data};

        case "map":
          return {t: "m", d: Object.values(value.data)};

        case "pid":
          return $.#serializeBoxedIdentifier("PID", "p", value, destination);

        case "port":
          return $.#serializeBoxedIdentifier("port", "o", value, destination);

        case "reference":
          return {t: "r", n: value.node, c: value.creation, i: value.idWords};

        case "tuple":
          return {t: "t", d: value.data};
      }

      const valueType = typeof value;

      if (valueType === "number" || valueType === "object") {
        return value;
      }

      // Cases ordered by expected frequency (most common first)
      switch (valueType) {
        case "object":
        case "number":
          return value;

        case "string":
          return $.#serializeJsString(value, key);

        case "function":
          return `u${value}`;
      }

      throw new HologramRuntimeError(
        `type "${valueType}" is not supported by the serializer`,
      );
    });

    return `[${$.CURRENT_VERSION},${serialized}]`;
  }

  static #serializeBoxedFunction(term, destination) {
    if (destination === "client") {
      return term;
    }

    if (term.capturedModule === null) {
      throw new HologramRuntimeError(
        "cannot serialize function: not a named function capture",
      );
    }

    return `c${term.capturedModule}${$.DELIMITER}${term.capturedFunction}${$.DELIMITER}${term.arity}`;
  }

  static #serializeBoxedIdentifier(typeName, typePrefix, term, destination) {
    if (term.origin === "client" && destination === "server") {
      throw new HologramRuntimeError(
        `cannot serialize ${typeName}: origin is client but destination is server`,
      );
    }

    return `${typePrefix}${term.node}${$.DELIMITER}${term.segments.join(",")}${$.DELIMITER}${term.origin}`;
  }

  static #serializeJsString(value, key) {
    // Don't add prefix for the type marker in serialized boxed collection types
    if (
      key === "t" &&
      (value === "l" || value === "m" || value === "r" || value === "t")
    ) {
      return value;
    }

    return `s${value}`;
  }
}

const $ = Serializer;

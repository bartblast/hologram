"use strict";

import Bitstring2 from "./bitstring2.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";

/*
Serializer Format Changelog

Release 0.5.0: switched to version 2.
*/

export default class Serializer {
  static CURRENT_VERSION = 2;

  // Can't use control characters in 0x00-0x1F range,
  // because they are escaped in JSON and result in multi-byte delimiter
  static DELIMITER = "\x80";

  static serialize(term, destination = "server") {
    const serialized = JSON.stringify(term, (key, value) => {
      const boxedTermType = value?.type;

      switch (boxedTermType) {
        case "anonymous_function":
          return $.#serializeBoxedFunction(value, destination);

        case "atom":
          return `a${value.value}`;

        case "bitstring2":
          return Bitstring2.serialize(value);

        case "float":
          return `f${value.value}`;

        case "integer":
          return `i${value.value}`;

        case "list":
          return {t: "l", d: value.data};

        case "map":
          return {t: "m", d: Object.values(value.data)};

        case "pid":
          return $.#serializeBoxedPid(value, destination);

        case "tuple":
          return {t: "t", d: value.data};
      }

      //       if (boxedTermType === "port") {
      //         return $.#serializeBoxedPort(value, isFullScope);
      //       }

      //       if (boxedTermType === "reference") {
      //         return $.#serializeBoxedReference(value, isFullScope);
      //       }

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
        "can't encode client terms that are anonymous functions that are not named function captures",
      );
    }

    // Function capture
    return `c${term.capturedModule}${$.DELIMITER}${term.capturedFunction}${$.DELIMITER}${term.arity}`;
  }

  static #serializeBoxedPid(term, destination) {
    if (destination === "client") {
      return term;
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "cannot serialize PID: origin is client but destination is server",
      );
    }

    // PID originating in server
    return `p${term.node}${$.DELIMITER}${term.segments.join(",")}${$.DELIMITER}${term.origin}`;
  }

  static #serializeJsString(value, key) {
    // Don't add prefix for the type marker in serialized boxed map and tuple objects
    if (key === "t" && (value === "l" || value === "m" || value === "t")) {
      return value;
    }

    return `s${value}`;
  }

  //   static #serializeBoxedPort(term, isFullScope) {
  //     if (isFullScope) {
  //       return term;
  //     }

  //     if (term.origin === "client") {
  //       throw new HologramRuntimeError(
  //         "can't encode client terms that are ports originating in client",
  //       );
  //     }

  //     // eslint-disable-next-line no-unused-vars
  //     const {origin, ...rest} = term;
  //     return rest;
  //   }

  //   static #serializeBoxedReference(term, isFullScope) {
  //     if (isFullScope) {
  //       return term;
  //     }

  //     if (term.origin === "client") {
  //       throw new HologramRuntimeError(
  //         "can't encode client terms that are references originating in client",
  //       );
  //     }

  //     // eslint-disable-next-line no-unused-vars
  //     const {origin, ...rest} = term;
  //     return rest;
  //   }
}

const $ = Serializer;

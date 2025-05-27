"use strict";

// import Bitstring2 from "./bitstring2.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";

/*
Serializer Format Changelog

Release 0.5.0: switched to version 2.
*/

export default class Serializer {
  static CURRENT_VERSION = 2;

  // When isFullScope is set to true, then everything is serialized,
  // including anonymous functions and all objects' fields (such as boxed PID node).
  static serialize(term) {
    const serialized = JSON.stringify(term, (_key, value) => {
      const boxedValueType = value?.type;

      //       if (boxedValueType === "anonymous_function") {
      //         return $.#serializeBoxedAnonymousFunction(value, isFullScope);
      //       }

      switch (boxedValueType) {
        case "atom":
          return `a${value.value}`;

        case "float":
          return `f${value.value}`;

        case "integer":
          return `i${value.value}`;
      }

      //       if (boxedValueType === "bitstring2") {
      //         return Bitstring2.serialize(value);
      //       }

      //       if (boxedValueType === "map") {
      //         return {t: "m", d: Object.values(value.data)};
      //       }

      //       if (boxedValueType === "pid") {
      //         return $.#serializeBoxedPid(value, isFullScope);
      //       }

      //       if (boxedValueType === "port") {
      //         return $.#serializeBoxedPort(value, isFullScope);
      //       }

      //       if (boxedValueType === "reference") {
      //         return $.#serializeBoxedReference(value, isFullScope);
      //       }

      //       if (boxedValueType === "tuple") {
      //         return {t: "t", d: value.data};
      //       }

      //       if (typeof value === "bigint") {
      //         return `__bigint__:${value.toString()}`;
      //       }

      //       return typeof value === "undefined" ? null : value;

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
          return `s${value}`;

        case "function":
          return `u${value}`;
      }

      throw new HologramRuntimeError(
        `type "${valueType}" is not supported by the serializer`,
      );
    });

    return `[${$.CURRENT_VERSION},${serialized}]`;
  }

  //   static #serializeBoxedAnonymousFunction(term, isFullScope) {
  //     if (isFullScope) {
  //       return term;
  //     }

  //     if (term.capturedModule === null) {
  //       throw new HologramRuntimeError(
  //         "can't encode client terms that are anonymous functions that are not named function captures",
  //       );
  //     }

  //     // eslint-disable-next-line no-unused-vars
  //     const {clauses, context, uniqueId, ...rest} = term;
  //     return rest;
  //   }

  //   static #serializeBoxedPid(term, isFullScope) {
  //     if (isFullScope) {
  //       return term;
  //     }

  //     if (term.origin === "client") {
  //       throw new HologramRuntimeError(
  //         "can't encode client terms that are PIDs originating in client",
  //       );
  //     }

  //     // eslint-disable-next-line no-unused-vars
  //     const {node, origin, ...rest} = term;
  //     return rest;
  //   }

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

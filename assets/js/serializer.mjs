"use strict";

import Bitstring2 from "./bitstring2.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";

/*
Serializer Format Changelog

Release 0.5.0: switched to version 2.
*/

export default class Serializer {
  // When isFullScope is set to true, then everything is serialized,
  // including anonymous functions and all objects' fields (such as boxed PID node).
  static serialize(term, isFullScope = true, isVersioned = true) {
    const serialized = JSON.stringify(term, (_key, value) => {
      const boxedValueType = value?.type;

      if (boxedValueType === "anonymous_function") {
        return $.#serializeBoxedAnonymousFunction(value, isFullScope);
      }

      if (boxedValueType === "atom") {
        return `a:${value.value}`;
      }

      if (boxedValueType === "bitstring2") {
        return Bitstring2.serialize(value);
      }

      if (boxedValueType === "float") {
        return `__float__:${value.value.toString()}`;
      }

      if (boxedValueType === "integer") {
        return `__integer__:${value.value.toString()}`;
      }

      if (boxedValueType === "map") {
        return {...value, data: Object.values(value.data)};
      }

      if (boxedValueType === "pid") {
        return $.#serializeBoxedPid(value, isFullScope);
      }

      if (boxedValueType === "port") {
        return $.#serializeBoxedPort(value, isFullScope);
      }

      if (boxedValueType === "reference") {
        return $.#serializeBoxedReference(value, isFullScope);
      }

      if (typeof value === "bigint") {
        return `__bigint__:${value.toString()}`;
      }

      if (typeof value === "function") {
        return `__function__:${value.toString()}`;
      }

      return typeof value === "undefined" ? null : value;
    });

    if (
      !serialized.startsWith('"') &&
      !serialized.startsWith("{") &&
      !serialized.startsWith("[") &&
      serialized !== "false" &&
      serialized !== "null" &&
      serialized !== "true" &&
      !/^\d/.test(serialized)
    ) {
      if (isVersioned) {
        // [version, data]
        return `[2,"${serialized}"]`;
      }

      return `"${serialized}"`;
    }

    if (isVersioned) {
      // [version, data]
      return `[2,${serialized}]`;
    }

    return serialized;
  }

  static #serializeBoxedAnonymousFunction(term, isFullScope) {
    if (isFullScope) {
      return term;
    }

    if (term.capturedModule === null) {
      throw new HologramRuntimeError(
        "can't encode client terms that are anonymous functions that are not named function captures",
      );
    }

    // eslint-disable-next-line no-unused-vars
    const {clauses, context, uniqueId, ...rest} = term;
    return rest;
  }

  static #serializeBoxedPid(term, isFullScope) {
    if (isFullScope) {
      return term;
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are PIDs originating in client",
      );
    }

    // eslint-disable-next-line no-unused-vars
    const {node, origin, ...rest} = term;
    return rest;
  }

  static #serializeBoxedPort(term, isFullScope) {
    if (isFullScope) {
      return term;
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are ports originating in client",
      );
    }

    // eslint-disable-next-line no-unused-vars
    const {origin, ...rest} = term;
    return rest;
  }

  static #serializeBoxedReference(term, isFullScope) {
    if (isFullScope) {
      return term;
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are references originating in client",
      );
    }

    // eslint-disable-next-line no-unused-vars
    const {origin, ...rest} = term;
    return rest;
  }
}

const $ = Serializer;

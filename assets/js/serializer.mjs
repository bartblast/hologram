"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Type from "./type.mjs";

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
        return `__atom__:${value.value}`;
      }

      if (boxedValueType === "bitstring") {
        return $.#serializeBoxedBitstring(value);
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
        return `[1,"${serialized}"]`;
      }

      return `"${serialized}"`;
    }

    if (isVersioned) {
      // [version, data]
      return `[1,${serialized}]`;
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

  static #serializeBoxedBitstring(term) {
    if (Type.isBinary(term)) {
      return `__binary__:${Bitstring.toText(term)}`;
    }

    return {...term, bits: Array.from(term.bits)};
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

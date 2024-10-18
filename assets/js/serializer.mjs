"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Type from "./type.mjs";

export default class Serializer {
  // When isFullScope is set to true, then everything is serialized,
  // including anonymous functions and all objects' fields (such as boxed PID node).
  static serialize(term, isFullScope = true) {
    const serialized = JSON.stringify(term, (_key, value) => {
      if (value?.type === "atom") {
        return `__atom__:${value.value}`;
      }

      if (value?.type === "bitstring") {
        return $.#serializeBoxedBitstring(value);
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

      if (value?.type === "port") {
        return $.#serializeBoxedPort(value, isFullScope);
      }

      if (value?.type === "reference") {
        return $.#serializeBoxedReference(value, isFullScope);
      }

      if (typeof value === "bigint") {
        return `__bigint__:${value.toString()}`;
      }

      return value;
    });

    if (
      !serialized.startsWith('"') &&
      !serialized.startsWith("{") &&
      !serialized.startsWith("[") &&
      !["false", "null", "true"].includes(serialized) &&
      !/^\d/.test(serialized)
    ) {
      // [version, data]
      return `[1,"${serialized}"]`;
    }

    // [version, data]
    return `[1,${serialized}]`;
  }

  static #serializeBoxedBitstring(term) {
    if (Type.isBinary(term)) {
      return `__binary__:${Bitstring.toText(term)}`;
    }

    return {...term, bits: Array.from(term.bits)};
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

    const {origin, ...rest} = term;
    return rest;
  }
}

const $ = Serializer;

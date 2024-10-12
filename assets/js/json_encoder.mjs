"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Type from "./type.mjs";

export default class JsonEncoder {
  // When isFullScope is set to true, then everything is serialized,
  // including anonymous functions and all objects' fields (such as boxed PID node).
  static encode(term, isFullScope = true) {
    if (term === null || typeof term === "undefined") {
      return "null";
    }

    switch (term.type) {
      case "anonymous_function":
        return JsonEncoder.#encodeAnonymousFunction(term);

      case "bitstring":
        return JsonEncoder.#encodeBitstring(term);

      case "integer":
        return JsonEncoder.encode(term.value);

      case "list":
        return JsonEncoder.#encodeList(term, isFullScope);

      case "map":
        return JsonEncoder.#encodeMap(term, isFullScope);

      case "pid":
        return JsonEncoder.#encodePid(term, isFullScope);

      case "port":
        return JsonEncoder.#encodePort(term, isFullScope);

      case "reference":
        return JsonEncoder.#encodeReference(term);

      case "tuple":
        return JsonEncoder.#encodeTuple(term, isFullScope);

      default:
        if (Array.isArray(term)) {
          return JsonEncoder.#encodeArray(term, isFullScope);
        }

        return JSON.stringify(term, (_key, value) => {
          if (typeof value === "bigint") {
            return `__integer__:${value.toString()}`;
          } else {
            return value;
          }
        });
    }
  }

  static #encodeAnonymousFunction(term) {
    if (term.capturedModule === null) {
      throw new HologramRuntimeError(
        "can't encode client terms that are anonymous functions that are not named function captures",
      );
    }

    return JSON.stringify({
      type: "anonymous_function",
      module: term.capturedModule,
      function: term.capturedFunction,
      arity: term.arity,
    });
  }

  static #encodeArray(term, isFullScope) {
    return `[${JsonEncoder.#encodeEnumData(term, isFullScope)}]`;
  }

  static #encodeBitstring(term) {
    if (Type.isBinary(term)) {
      return `"__binary__:${JsonEncoder.#escapeDoubleQuotes(Bitstring.toText(term))}"`;
    }

    return JSON.stringify({type: "bitstring", bits: Array.from(term.bits)});
  }

  static #encodeEnumData(data, isFullScope) {
    return data.map((item) => JsonEncoder.encode(item, isFullScope)).join(",");
  }

  static #encodeList(term, isFullScope) {
    return `{"type":"list","data":[${JsonEncoder.#encodeEnumData(term.data, isFullScope)}]}`;
  }

  static #encodeMap(term, isFullScope) {
    const dataOutput = Object.values(term.data)
      .map(
        ([key, value]) =>
          `[${JsonEncoder.encode(key, isFullScope)},${JsonEncoder.encode(value, isFullScope)}]`,
      )
      .join(",");

    return `{"type":"map","data":[${dataOutput}]}`;
  }

  static #encodePid(term, isFullScope) {
    if (isFullScope) {
      return JSON.stringify(term);
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are PIDs originating in client",
      );
    }

    return `{"type":"pid","segments":${JsonEncoder.encode(term.segments)}}`;
  }

  static #encodePort(term, isFullScope) {
    if (isFullScope) {
      return JSON.stringify(term);
    }

    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are ports originating in client",
      );
    }

    return `{"type":"port","value":"${term.value}"}`;
  }

  static #encodeReference(term) {
    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are references originating in client",
      );
    }

    return `{"type":"reference","value":"${term.value}"}`;
  }

  static #encodeTuple(term, isFullScope) {
    return `{"type":"tuple","data":[${JsonEncoder.#encodeEnumData(term.data, isFullScope)}]}`;
  }

  static #escapeDoubleQuotes(str) {
    return str.replace(/"/g, '\\"');
  }
}

"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Type from "./type.mjs";

export default class JsonEncoder {
  static encode(term) {
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
        return JsonEncoder.#encodeList(term);

      case "map":
        return JsonEncoder.#encodeMap(term);

      case "pid":
        return JsonEncoder.#encodePid(term);

      case "port":
        return JsonEncoder.#encodePort(term);

      case "reference":
        return JsonEncoder.#encodeReference(term);

      case "tuple":
        return JsonEncoder.#encodeTuple(term);

      default:
        if (Array.isArray(term)) {
          return JsonEncoder.#encodeArray(term);
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

  static #encodeArray(term) {
    return `[${JsonEncoder.#encodeEnumData(term)}]`;
  }

  static #encodeBitstring(term) {
    if (Type.isBinary(term)) {
      return `"__binary__:${JsonEncoder.#escapeDoubleQuotes(Bitstring.toText(term))}"`;
    }

    return JSON.stringify({type: "bitstring", bits: Array.from(term.bits)});
  }

  static #encodeEnumData(data) {
    return data.map((item) => JsonEncoder.encode(item)).join(",");
  }

  static #encodeList(term) {
    return `{"type":"list","data":[${JsonEncoder.#encodeEnumData(term.data)}]}`;
  }

  static #encodeMap(term) {
    const dataOutput = Object.values(term.data)
      .map(
        ([key, value]) =>
          `[${JsonEncoder.encode(key)},${JsonEncoder.encode(value)}]`,
      )
      .join(",");

    return `{"type":"map","data":[${dataOutput}]}`;
  }

  static #encodePid(term) {
    if (term.origin === "client") {
      throw new HologramRuntimeError(
        "can't encode client terms that are PIDs originating in client",
      );
    }

    return `{"type":"pid","segments":${JsonEncoder.encode(term.segments)}}`;
  }

  static #encodePort(term) {
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

  static #encodeTuple(term) {
    return `{"type":"tuple","data":[${JsonEncoder.#encodeEnumData(term.data)}]}`;
  }

  static #escapeDoubleQuotes(str) {
    return str.replace(/"/g, '\\"');
  }
}

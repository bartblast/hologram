"use strict";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Type from "./type.mjs";

export default class Serializer {
  static serialize(term) {
    if (term === null) {
      return "null";
    }

    switch (term.type) {
      case "anonymous_function":
        throw new HologramInterpreterError(
          "can't serialize boxed anonymous functions",
        );

      case "bitstring":
        return Serializer.#serializeBitstring(term);

      case "integer":
        return `"__integer__:${term.value.toString()}"`;

      case "list":
        return Serializer.#serializeList(term);

      case "map":
        return Serializer.#serializeMap(term);

      case "pid":
        return Serializer.#serializePid(term);

      case "port":
        return Serializer.#serializePort(term);

      case "reference":
        return Serializer.#serializeReference(term);

      case "tuple":
        return Serializer.#serializeTuple(term);

      default:
        return JSON.stringify(term, (_key, value) => {
          if (typeof value === "bigint") {
            return `__integer__:${value.toString()}`;
          } else {
            return value;
          }
        });
    }
  }

  static #escapeDoubleQuotes(str) {
    return str.replace(/"/g, '\\"');
  }

  static #serializeBitstring(term) {
    if (Type.isBinary(term)) {
      return `"__binary__:${Serializer.#escapeDoubleQuotes(Bitstring.toText(term))}"`;
    }

    return JSON.stringify(term);
  }

  static #serializeEnumData(data) {
    return data.map((item) => Serializer.serialize(item)).join(",");
  }

  static #serializeList(term) {
    return `{"type":"list",data:[${Serializer.#serializeEnumData(term.data)}]}`;
  }

  static #serializeMap(term) {
    const dataOutput = Object.values(term.data)
      .map(
        ([key, value]) =>
          `[${Serializer.serialize(key)},${Serializer.serialize(value)}]`,
      )
      .join(",");

    return `{"type":"map",data:[${dataOutput}]}`;
  }

  static #serializePid(term) {
    if (term.origin === "client") {
      throw new HologramInterpreterError(
        "can't serialize PIDs originating in client",
      );
    }

    return `{"type":"pid","node":"${Serializer.#escapeDoubleQuotes(term.node)}","segments":${Serializer.serialize(term.segments)}}`;
  }

  static #serializePort(term) {
    if (term.origin === "client") {
      throw new HologramInterpreterError(
        "can't serialize ports originating in client",
      );
    }

    return `{"type":"port","value":"${term.value}"}`;
  }

  static #serializeReference(term) {
    if (term.origin === "client") {
      throw new HologramInterpreterError(
        "can't serialize references originating in client",
      );
    }

    return `{"type":"reference","value":"${term.value}"}`;
  }

  static #serializeTuple(term) {
    return `{"type":"tuple",data:[${Serializer.#serializeEnumData(term.data)}]}`;
  }
}

"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual.js";

import Type from "./type.mjs";

export default class Interpreter {
  static consOperator(left, right) {
    return Type.list([left].concat(right.data));
  }

  static count(enumerable) {
    if (Type.isMap(enumerable)) {
      return Object.keys(enumerable.data).length;
    }

    return enumerable.data.length;
  }

  static head(list) {
    return list.data[0];
  }

  // TODO: use Kernel.inspect/2 instead
  static inspect(term) {
    switch (term.type) {
      case "atom":
        return ":" + term.value;

      // TODO: case "bitstring"

      case "float":
      case "integer":
        return term.value.toString();

      case "list":
        return (
          "[" +
          term.data.map((item) => Interpreter.inspect(item)).join(", ") +
          "]"
        );

      case "string":
        return '"' + term.value.toString() + '"';

      case "tuple":
        return (
          "{" +
          term.data.map((item) => Interpreter.inspect(item)).join(", ") +
          "}"
        );

      default:
        return JSON.stringify(term);
    }
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  static raiseError(type, message) {
    throw new Error(`(${type}) ${message}`);
  }

  static raiseNotYetImplementedError(message) {
    Interpreter.raiseError("Hologram.NotYetImplementedError", `${message}`);
  }

  static tail(list) {
    return Type.list(list.data.slice(1));
  }
}

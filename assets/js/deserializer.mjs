"use strict";

import Bitstring from "./bitstring.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Deserializer {
  static deserialize(serialized) {
    return JSON.parse(serialized, (_key, value) => {
      return typeof value === "string"
        ? $.#maybeDeserializeFromString(value)
        : $.#maybeDeserializeFromObject(value);
    })[1];
  }

  static #deserializeBoxedBitstring(serialized) {
    if (serialized === "b") {
      return Type.bitstring("");
    }

    const hex = serialized.slice(2);
    const hexLength = hex.length;
    const bytes = new Uint8Array(hexLength >> 1);

    // Use separate j index variable to avoid division in each iteration
    for (let i = 0, j = 0; i < hexLength; i += 2, j++) {
      bytes[j] = parseInt(hex.slice(i, i + 2), 16);
    }

    const bitstring = Bitstring.fromBytes(bytes);
    bitstring.leftoverBitCount = parseInt(serialized[1]);

    return bitstring;
  }

  static #deserializeBoxedFunctionCapture(serialized) {
    const parts = serialized.split(Serializer.DELIMITER);
    const context = Interpreter.buildContext();

    return Type.functionCapture(
      parts[0],
      parts[1],
      parseInt(parts[2]),
      [],
      context,
    );
  }

  static #deserializeBoxedIdentifier(identifierType, serialized) {
    const parts = serialized.split(Serializer.DELIMITER);

    return Type[identifierType](
      parts[0],
      parts[1].split(",").map((segment) => parseInt(segment)),
      parts[2],
    );
  }

  static #maybeDeserializeFromObject(obj) {
    switch (obj?.t) {
      case "l":
        return Type.list(obj.d);

      case "m":
        return Type.map(obj.d);

      case "r":
        return Type.reference(obj.n, obj.c, obj.i);

      case "t":
        return Type.tuple(obj.d);
    }

    return obj;
  }

  static #maybeDeserializeFromString(serialized) {
    const data = serialized.slice(1);

    switch (serialized[0]) {
      case "a":
        return Type.atom(data);

      case "b":
        return $.#deserializeBoxedBitstring(serialized);

      case "c":
        return $.#deserializeBoxedFunctionCapture(data);

      case "f":
        return Type.float(Number(data));

      case "i":
        return Type.integer(BigInt(data));

      case "o":
        return $.#deserializeBoxedIdentifier("port", data);

      case "p":
        return $.#deserializeBoxedIdentifier("pid", data);

      case "s":
        return data;

      case "u":
        return Interpreter.evaluateJavaScriptExpression(data);
    }

    return serialized;
  }
}

const $ = Deserializer;

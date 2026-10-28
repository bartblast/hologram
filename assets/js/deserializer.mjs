"use strict";

import Bitstring from "./bitstring.mjs";
import ERTS from "./erts.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Deserializer {
  // Reads a value serialized by Serializer.serialize or by the server, given as the serialized
  // text or as the [version, data] array the text parses to, which is how a term arrives as a
  // field of a response the client has already parsed.
  //
  // The text is parsed plain and the result walked: JSON.parse takes a slow path when given a
  // reviver, and a walk over the parsed value builds the same terms in a quarter of the time.
  //
  // The version decides what an "s" string is: a string under version 4, a plain JavaScript string
  // under version 3, the form stored by earlier releases.
  static deserialize(serialized) {
    const [version, data] =
      typeof serialized === "string" ? JSON.parse(serialized) : serialized;

    return $.#deserializeValue(data, version);
  }

  static #deserializeBoxedBitstring(serialized) {
    if (serialized === "b") {
      return Type.bitstring("");
    }

    const bitstring = Bitstring.fromHex(serialized.slice(2));
    bitstring.leftoverBitCount = parseInt(serialized[1]);

    return bitstring;
  }

  // The capture is built the way :erlang.make_fun/3 builds one, so it can be called: its one
  // clause calls the named function with the arity's worth of arguments. An Erlang module is
  // written with a leading colon, an Elixir module without its Elixir prefix.
  static #deserializeBoxedFunctionCapture(serialized) {
    const [capturedModule, functionName, arity] = serialized.split(
      Serializer.DELIMITER,
    );

    const module = capturedModule.startsWith(":")
      ? Type.atom(capturedModule.slice(1))
      : Type.atom(`Elixir.${capturedModule}`);

    return Interpreter.buildFunctionCapture(
      module,
      Type.atom(functionName),
      parseInt(arity),
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

  // Walks a parsed JSON value bottom-up: the items of a collection are read before the collection
  // is built from them, as a reviver would read them.
  static #deserializeValue(value, version) {
    if (typeof value === "string") {
      return $.#maybeDeserializeFromString(value, version);
    }

    if (Array.isArray(value)) {
      return value.map((item) => $.#deserializeValue(item, version));
    }

    if (value !== null && typeof value === "object") {
      return $.#deserializeObject(value, version);
    }

    return value;
  }

  // An object labelled by its "t" key is a boxed collection or a reference, any other object is a
  // plain JavaScript object whose properties hold values of their own and is walked in place.
  static #deserializeObject(obj, version) {
    switch (obj.t) {
      case "l":
        return Type.list($.#deserializeValue(obj.d, version));

      case "m": {
        const map = Type.map($.#deserializeValue(obj.d, version));
        $.#maybeRegisterRegexPattern(map);

        return map;
      }

      case "r":
        return Type.reference(
          $.#maybeDeserializeFromString(obj.n, version),
          obj.c,
          obj.i,
        );

      case "t":
        return Type.tuple($.#deserializeValue(obj.d, version));
    }

    for (const key in obj) {
      obj[key] = $.#deserializeValue(obj[key], version);
    }

    return obj;
  }

  static #maybeDeserializeFromString(serialized, version) {
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

      case "j":
        return data;

      case "o":
        return $.#deserializeBoxedIdentifier("port", data);

      case "p":
        return $.#deserializeBoxedIdentifier("pid", data);

      case "s":
        return version === 3 ? data : Type.bitstring(data);

      case "u":
        return Interpreter.evaluateJavaScriptExpression(data);
    }

    return serialized;
  }

  // A Regex struct carries its pattern source and compile options, so the
  // compiled pattern registered on the sender side is rebuilt here under
  // the same ref. Registration is skipped when the ref is already known,
  // which makes round-tripped client structs a no-op.
  static #maybeRegisterRegexPattern(map) {
    if (!Type.isStruct(map, "Regex")) return;

    const ref = $.#regexStructField(map, "re_pattern").data[4];

    if (ERTS.regexPatternRegistry.get(ref) !== null) return;

    const source = $.#regexStructField(map, "source");
    const opts = $.#regexStructField(map, "opts");

    const result = Interpreter.moduleProxy("re")["compile/2"](source, opts);
    const compiledRef = result.data[1].data[4];

    ERTS.regexPatternRegistry.put(
      ref,
      ERTS.regexPatternRegistry.get(compiledRef),
    );
  }

  static #regexStructField(map, key) {
    return map.data[Type.encodeMapKey(Type.atom(key))][1];
  }
}

const $ = Deserializer;

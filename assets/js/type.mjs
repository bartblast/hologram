"use strict";

import Bitstring from "./bitstring.mjs";
import Bitstring2 from "./bitstring2.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Sequence from "./sequence.mjs";
import Serializer from "./serializer.mjs";

export default class Type {
  static actionStruct(data = {}) {
    let {name, params, target} = data;

    if (typeof name === "undefined") {
      name = Type.nil();
    }

    if (typeof params === "undefined") {
      params = Type.map();
    }

    if (typeof target === "undefined") {
      target = Type.nil();
    }

    return Type.struct("Hologram.Component.Action", [
      [Type.atom("name"), name],
      [Type.atom("params"), params],
      [Type.atom("target"), target],
    ]);
  }

  static alias(aliasStr) {
    return Type.atom(`Elixir.${aliasStr}`);
  }

  static anonymousFunction(arity, clauses, context) {
    return {
      type: "anonymous_function",
      arity: arity,
      capturedFunction: null,
      capturedModule: null,
      clauses: clauses,
      context: Interpreter.cloneContext(context),
      uniqueId: Sequence.next(),
    };
  }

  static atom(value) {
    return {type: "atom", value: value};
  }

  static bitstring(data) {
    if (typeof data === "string") {
      return Type.bitstring([
        Type.bitstringSegment(Type.string(data), {type: "utf8"}),
      ]);
    } else if (data.length > 0 && typeof data[0] === "object") {
      return Bitstring.from(data);
    } else {
      return {type: "bitstring", bits: new Uint8Array(data)};
    }
  }

  // TODO: test
  static bitstring2(arg) {
    if (typeof arg === "string") {
      return Bitstring2.fromText(arg);
    }

    if (arg.length > 0 && typeof arg[0] === "object") {
      return Bitstring2.fromSegments(arg);
    }

    return Bitstring2.fromBits(arg);
  }

  static bitstringPattern(segments) {
    return {type: "bitstring_pattern", segments: segments};
  }

  static bitstringSegment(value, modifiers = {}) {
    const type = Type.#getOption(modifiers, "type");

    // TODO: is this needed?
    if (type === null) {
      throw new HologramInterpreterError(
        "bitstring segment type modifier is not specified",
      );
    }

    const size = Type.#getOption(modifiers, "size");
    const unit = Type.#getOption(modifiers, "unit");
    const signedness = Type.#getOption(modifiers, "signedness");
    const endianness = Type.#getOption(modifiers, "endianness");

    return {value, type, size, unit, signedness, endianness};
  }

  static boolean(value) {
    return Type.atom(value.toString());
  }

  static commandStruct(data = {}) {
    let {name, params, target} = data;

    if (typeof name === "undefined") {
      name = Type.nil();
    }

    if (typeof params === "undefined") {
      params = Type.map();
    }

    if (typeof target === "undefined") {
      target = Type.nil();
    }

    return Type.struct("Hologram.Component.Command", [
      [Type.atom("name"), name],
      [Type.atom("params"), params],
      [Type.atom("target"), target],
    ]);
  }

  static componentStruct(data = {}) {
    let {emittedContext, nextAction, nextCommand, nextPage, state} = data;

    if (typeof emittedContext === "undefined") {
      emittedContext = Type.map();
    }

    if (typeof nextAction === "undefined") {
      nextAction = Type.nil();
    }

    if (typeof nextCommand === "undefined") {
      nextCommand = Type.nil();
    }

    if (typeof nextPage === "undefined") {
      nextPage = Type.nil();
    }

    if (typeof state === "undefined") {
      state = Type.map();
    }

    return Type.struct("Hologram.Component", [
      [Type.atom("emitted_context"), emittedContext],
      [Type.atom("next_action"), nextAction],
      [Type.atom("next_command"), nextCommand],
      [Type.atom("next_page"), nextPage],
      [Type.atom("state"), state],
    ]);
  }

  static consPattern(head, tail) {
    return {type: "cons_pattern", head: head, tail: tail};
  }

  static encodeMapKey(term) {
    switch (term.type) {
      case "anonymous_function":
        return Type.#encodeAnonymousFunctionTypeMapKey(term);

      case "atom":
      case "float":
      case "integer":
        return Type.#encodePrimitiveTypeMapKey(term);

      case "bitstring":
        return Type.#encodeBitstringTypeMapKey(term);

      case "list":
      case "tuple":
        return Type.#encodeEnumTypeMapKey(term);

      case "map":
        return Type.#encodeMapTypeMapKey(term);
    }
  }

  static errorStruct(aliasStr, message) {
    const data = [
      [Type.atom("__exception__"), Type.boolean(true)],
      [Type.atom("message"), Type.bitstring(message)],
    ];

    return Type.struct(aliasStr, data);
  }

  static float(value) {
    return {type: "float", value: value};
  }

  static functionCapture(
    capturedModule,
    capturedFunction,
    arity,
    clauses,
    context,
  ) {
    return {
      type: "anonymous_function",
      arity: arity,
      capturedFunction: capturedFunction,
      capturedModule: capturedModule,
      clauses: clauses,
      context: Interpreter.buildContext({module: context.module, vars: {}}),
      uniqueId: Sequence.next(),
    };
  }

  static improperList(data) {
    if (data.length < 2) {
      throw new HologramInterpreterError(
        "improper list must have at least 2 items, received " +
          Serializer.serialize(data, true, false),
      );
    }

    return {type: "list", data: data, isProper: false};
  }

  static integer(value) {
    if (typeof value !== "bigint") {
      value = BigInt(value);
    }

    return {type: "integer", value: value};
  }

  static isAlias(term) {
    return Type.isAtom(term) && term.value.startsWith("Elixir.");
  }

  static isAnonymousFunction(term) {
    return term.type === "anonymous_function";
  }

  static isAtom(term) {
    return term.type === "atom";
  }

  static isBinary(term) {
    return Type.isBitstring(term) && term.bits.length % 8 === 0;
  }

  static isBitstring(term) {
    return term.type === "bitstring";
  }

  static isBitstringPattern(term) {
    return term.type === "bitstring_pattern";
  }

  static isBoolean(term) {
    return (
      term.type === "atom" && (term.value === "false" || term.value === "true")
    );
  }

  static isConsPattern(term) {
    return term.type === "cons_pattern";
  }

  static isFalse(term) {
    return Type.isAtom(term) && term.value === "false";
  }

  static isFalsy(term) {
    return Type.isFalse(term) || Type.isNil(term);
  }

  static isFloat(term) {
    return term.type === "float";
  }

  static isImproperList(term) {
    return Type.isList(term) && term.isProper === false;
  }

  static isInteger(term) {
    return term.type === "integer";
  }

  static isIterator(term) {
    if (Type.isTuple(term) && term.data.length === 3) {
      return true;
    }

    if (
      Type.isImproperList(term) &&
      term.data.length === 2 &&
      Type.isInteger(term.data[0]) &&
      Type.isMap(term.data[1])
    ) {
      return true;
    }

    if (Interpreter.isEqual(term, Type.atom("none"))) {
      return true;
    }

    return false;
  }

  static isKeywordList(term) {
    if (!Type.isList(term)) {
      return false;
    }

    return term.data.every(
      (item) =>
        Type.isTuple(item) &&
        item.data.length === 2 &&
        Type.isAtom(item.data[0]),
    );
  }

  static isList(term) {
    return term.type === "list";
  }

  static isMap(term) {
    return term.type === "map";
  }

  static isMatchPlaceholder(term) {
    return term.type === "match_placeholder";
  }

  static isNil(term) {
    return term.type === "atom" && term.value === "nil";
  }

  static isNumber(term) {
    return Type.isInteger(term) || Type.isFloat(term);
  }

  static isPid(term) {
    return term.type === "pid";
  }

  static isPort(term) {
    return term.type === "port";
  }

  static isProperList(term) {
    return Type.isList(term) && term.isProper === true;
  }

  // Deps: [:maps.get/3]
  static isRange(term) {
    return (
      Type.isMap(term) &&
      Interpreter.isEqual(
        Erlang_Maps["get/3"](Type.atom("__struct__"), term, Type.nil()),
        Type.alias("Range"),
      )
    );
  }

  static isReference(term) {
    return term.type === "reference";
  }

  // Deps: [:maps.is_key/2]
  static isStruct(term) {
    return (
      Type.isMap(term) &&
      Type.isTrue(Erlang_Maps["is_key/2"](Type.atom("__struct__"), term))
    );
  }

  static isTrue(term) {
    return Type.isAtom(term) && term.value === "true";
  }

  static isTruthy(term) {
    return !Type.isFalsy(term);
  }

  static isTuple(term) {
    return term.type === "tuple";
  }

  static isVariablePattern(term) {
    return term.type === "variable_pattern";
  }

  static list(data = []) {
    return {type: "list", data: data, isProper: true};
  }

  static keywordList(data = []) {
    return Type.list(data.map((item) => Type.tuple(item)));
  }

  static map(data = []) {
    const hashTableWithMetadata = data.reduce((acc, [key, value]) => {
      acc[Type.encodeMapKey(key)] = [key, value];
      return acc;
    }, {});

    return {type: "map", data: hashTableWithMetadata};
  }

  static matchPlaceholder() {
    return {type: "match_placeholder"};
  }

  static nil() {
    return Type.atom("nil");
  }

  static maybeNormalizeNumberTerms(term1, term2) {
    const type =
      Type.isFloat(term1) || Type.isFloat(term2) ? "float" : "integer";

    let value1, value2;

    if (type === "float" && Type.isInteger(term1)) {
      value1 = Type.float(Number(term1.value));
    } else {
      value1 = term1;
    }

    if (type === "float" && Type.isInteger(term2)) {
      value2 = Type.float(Number(term2.value));
    } else {
      value2 = term2;
    }

    return [type, value1, value2];
  }

  static pid(node, segments, origin = "server") {
    return {type: "pid", node: node, origin: origin, segments: segments};
  }

  static port(value, origin = "server") {
    return {type: "port", origin: origin, value: value};
  }

  static range(first, last, step) {
    return Type.struct("Range", [
      [Type.atom("first"), Type.integer(first)],
      [Type.atom("last"), Type.integer(last)],
      [Type.atom("step"), Type.integer(step)],
    ]);
  }

  static reference(value, origin = "server") {
    return {type: "reference", origin: origin, value: value};
  }

  static string(value) {
    return {type: "string", value: value};
  }

  static struct(aliasStr, data) {
    const key = Type.atom("__struct__");
    const value = Type.alias(aliasStr);

    return Type.map(data.concat([[key, value]]));
  }

  static tuple(data = []) {
    return {type: "tuple", data: data};
  }

  static variablePattern(name) {
    return {type: "variable_pattern", name: name};
  }

  static #encodeAnonymousFunctionTypeMapKey(anonymousFunction) {
    return "anonymous_function(" + anonymousFunction.uniqueId + ")";
  }

  static #encodeBitstringTypeMapKey(bitstring) {
    return "bitstring(" + bitstring.bits.join("") + ")";
  }

  static #encodeEnumTypeMapKey(term) {
    const itemsStr = term.data.map((item) => Type.encodeMapKey(item)).join(",");

    return term.type + "(" + itemsStr + ")";
  }

  static #encodeMapTypeMapKey(map) {
    const itemsStr = Object.keys(map.data)
      .sort()
      .map((key) => key + ":" + Type.encodeMapKey(map.data[key][1]))
      .join(",");

    return "map(" + itemsStr + ")";
  }

  static #encodePrimitiveTypeMapKey(term) {
    return `${term.type}(${term.value})`;
  }

  static #getOption(options, key) {
    return typeof options[key] !== "undefined" ? options[key] : null;
  }
}

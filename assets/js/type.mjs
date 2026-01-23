"use strict";

import Bitstring from "./bitstring.mjs";
import ERTS from "./erts.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import Interpreter from "./interpreter.mjs";
import Sequence from "./sequence.mjs";
import Serializer from "./serializer.mjs";
import Utils from "./utils.mjs";

export default class Type {
  static actionStruct(data = {}) {
    let {name, params, target, delay} = data;

    if (typeof name === "undefined") {
      name = Type.nil();
    }

    if (typeof params === "undefined") {
      params = Type.map();
    }

    if (typeof target === "undefined") {
      target = Type.nil();
    }

    if (typeof delay === "undefined") {
      delay = Type.integer(0);
    }

    return Type.struct("Hologram.Component.Action", [
      [Type.atom("name"), name],
      [Type.atom("params"), params],
      [Type.atom("target"), target],
      [Type.atom("delay"), delay],
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

  static bitstring(arg) {
    if (typeof arg === "string") {
      return Bitstring.fromText(arg);
    }

    if (arg.length > 0 && typeof arg[0] === "object") {
      return Bitstring.fromSegments(arg);
    }

    return Bitstring.fromBits(arg);
  }

  static bitstringPattern(segments) {
    return {type: "bitstring_pattern", segments: segments};
  }

  static bitstringSegment(value, modifiers = {}) {
    const type = Type.#getOption(modifiers, "type");
    const size = Type.#getOption(modifiers, "size");
    const unit = Type.#getOption(modifiers, "unit");
    const signedness = Type.#getOption(modifiers, "signedness");
    const endianness = Type.#getOption(modifiers, "endianness");

    return {value, type, size, unit, signedness, endianness};
  }

  static boolean(value) {
    return Type.atom(value.toString());
  }

  static charlist(string) {
    return Type.list(
      Array.from(string, (char) => Type.integer(char.codePointAt(0))),
    );
  }

  static cloneMap(map) {
    return {type: "map", data: Utils.shallowCloneObject(map.data)};
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
        return Bitstring.serialize(term);

      case "list":
      case "tuple":
        return Type.#encodeEnumTypeMapKey(term);

      case "map":
        return Type.#encodeMapTypeMapKey(term);

      case "reference":
        return Type.#encodeReferenceTypeMapKey(term);
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
          Serializer.serialize(data, "client"),
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
    return Type.isBitstring(term) && term.leftoverBitCount === 0;
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

  static isCharlist(term) {
    if (!Type.isProperList(term)) {
      return false;
    }

    return term.data.every(
      (elem) => Type.isInteger(elem) && Bitstring.validateCodePoint(elem.value),
    );
  }

  static isCompiledPattern(term) {
    if (!Type.isTuple(term)) return false;

    const data = term.data;
    if (data.length !== 2) return false;

    const algo = data[0];

    return (
      Type.isAtom(algo) &&
      (algo.value === "bm" || algo.value === "ac") &&
      Type.isReference(data[1])
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

  static port(node, segments, origin = "server") {
    return {type: "port", node: node, origin: origin, segments: segments};
  }

  static range(first, last, step) {
    return Type.struct("Range", [
      [Type.atom("first"), Type.integer(first)],
      [Type.atom("last"), Type.integer(last)],
      [Type.atom("step"), Type.integer(step)],
    ]);
  }

  static reference(node, creation, idWords) {
    return {
      type: "reference",
      node: node,
      creation: creation,
      idWords: idWords,
    };
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

  static #encodeReferenceTypeMapKey(term) {
    const localIncarnationId = ERTS.nodeTable.getLocalIncarnationId(
      term.node,
      term.creation,
    );

    return `r${localIncarnationId}.${term.idWords.toReversed().join(".")}`;
  }

  static #getOption(options, key) {
    return typeof options[key] !== "undefined" ? options[key] : null;
  }
}

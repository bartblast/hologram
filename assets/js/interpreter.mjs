"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep.js";
import isEqual from "lodash/isEqual.js";
import omit from "lodash/omit.js";
import uniqWith from "lodash/uniqWith.js";

import Bitstring from "./bitstring.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramMatchError from "./errors/match_error.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Interpreter {
  static callAnonymousFunction(fun, argsArray) {
    const args = Type.list(argsArray);

    for (const clause of fun.clauses) {
      const varsClone = Interpreter.cloneVars(fun.vars);
      const pattern = Type.list(clause.params(varsClone));

      if (
        Interpreter.isMatched(pattern, args, varsClone) &&
        Interpreter.#evaluateGuards(clause.guards, varsClone)
      ) {
        return clause.body(varsClone);
      }
    }

    // TODO: include parent module and function info, once context for error reporting is implemented.
    const message = "no function clause matching in anonymous fn/" + fun.arity;
    return Interpreter.#raiseFunctionClauseError(message);
  }

  static callNamedFunction(alias, functionArityStr, args) {
    return Interpreter.module(alias)[functionArityStr](...args);
  }

  static case(condition, clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Interpreter.cloneVars(vars);

      if (
        Interpreter.isMatched(clause.match, condition, varsClone) &&
        Interpreter.#evaluateGuards(clause.guards, varsClone)
      ) {
        return clause.body(varsClone);
      }
    }

    const message =
      "no case clause matching: " + Interpreter.inspect(condition);

    return Interpreter.#raiseCaseClauseError(message);
  }

  static cloneVars(vars) {
    return cloneDeep(omit(vars, ["__snapshot__"]));
  }

  static comprehension(generators, filters, collectable, unique, mapper, vars) {
    const generatorsCount = generators.length;

    const sets = generators.map(
      (generator) => Elixir_Enum["to_list/1"](generator.body(vars)).data,
    );

    let items = Utils.cartesianProduct(sets).reduce((acc, combination) => {
      const varsClone = Interpreter.cloneVars(vars);

      for (let i = 0; i < generatorsCount; ++i) {
        if (
          !Interpreter.isMatched(
            generators[i].match,
            combination[i],
            varsClone,
          ) ||
          !Interpreter.#evaluateGuards(generators[i].guards, varsClone)
        ) {
          return acc;
        }
      }

      for (const filter of filters) {
        if (Type.isFalsy(filter(varsClone))) {
          return acc;
        }
      }

      acc.push(mapper(varsClone));
      return acc;
    }, []);

    if (unique) {
      items = uniqWith(items, Interpreter.isStrictlyEqual);
    }

    return Elixir_Enum["into/2"](Type.list(items), collectable);
  }

  static cond(clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Interpreter.cloneVars(vars);

      if (Type.isTruthy(clause.condition(varsClone))) {
        return clause.body(varsClone);
      }
    }

    return Interpreter.#raiseCondClauseError();
  }

  static consOperator(head, tail) {
    if (Type.isProperList(tail)) {
      return Type.list([head].concat(tail.data));
    } else {
      return Type.improperList([head, tail]);
    }
  }

  static defineElixirFunction(
    moduleName,
    functionName,
    functionArity,
    clauses,
  ) {
    if (!globalThis[moduleName]) {
      globalThis[moduleName] = {};
    }

    globalThis[moduleName][`${functionName}/${functionArity}`] = function () {
      const args = Type.list([...arguments]);
      const arity = arguments.length;

      for (const clause of clauses) {
        const vars = {};
        const pattern = Type.list(clause.params(vars));

        if (
          Interpreter.isMatched(pattern, args, vars) &&
          Interpreter.#evaluateGuards(clause.guards, vars)
        ) {
          return clause.body(vars);
        }
      }

      const inspectedModuleName = Interpreter.inspectModuleName(moduleName);
      const message = `no function clause matching in ${inspectedModuleName}.${functionName}/${arity}`;
      Interpreter.#raiseFunctionClauseError(message);
    };
  }

  static defineErlangFunction(
    moduleName,
    functionName,
    functionArity,
    jsFunction,
  ) {
    if (!globalThis[moduleName]) {
      globalThis[moduleName] = {};
    }

    globalThis[moduleName][`${functionName}/${functionArity}`] = jsFunction;
  }

  static defineNotImplementedErlangFunction(
    exModuleName,
    jsModuleName,
    functionName,
    functionArity,
  ) {
    if (!globalThis[jsModuleName]) {
      globalThis[jsModuleName] = {};
    }

    globalThis[jsModuleName][`${functionName}/${functionArity}`] = () => {
      // TODO: update the URL
      const message = `Function :${exModuleName}.${functionName}/${functionArity} is not yet ported. See what to do here: https://www.hologram.page/TODO`;

      throw new HologramInterpreterError(message);
    };
  }

  static deserialize(json) {
    return JSON.parse(json, (_key, value) => {
      if (typeof value === "string" && /^__bigint__:-?\d+$/.test(value)) {
        return BigInt(value.substring(11, value.length));
      }
      return value;
    });
  }

  static dotOperator(left, right) {
    // if left argument is a boxed atom, treat the operator as a remote function call
    if (Type.isAtom(left)) {
      const functionArityStr = `${right.value}/0`;
      return Interpreter.module(left)[functionArityStr]();
    }

    // otherwise treat the operator as map key access
    return Erlang_maps["get/2"](right, left);
  }

  static fetchErrorMessage(jsError) {
    // TODO: use transpiled Elixir code
    return Bitstring.toText(jsError.struct.data["atom(message)"][1]);
  }

  static fetchErrorType(jsError) {
    // TODO: use transpiled Elixir code
    return jsError.struct.data["atom(__struct__)"][1].value.substring(7);
  }

  static inspect(term) {
    return Elixir_Kernel["inspect/2"](term, Type.list([]));
  }

  static inspectModuleName(moduleName) {
    if (moduleName.startsWith("Elixir_")) {
      return moduleName.slice(7).replace("_", ".");
    }

    if (moduleName === "Erlang") {
      return ":erlang";
    }

    // starts with "Erlang_"
    return ":" + moduleName.slice(7).toLowerCase();
  }

  static isMatched(left, right, vars, rootMatch = true) {
    try {
      Interpreter.matchOperator(right, left, vars, rootMatch);
      return true;
    } catch {
      return false;
    }
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  // vars.__matched__ keeps track of already pattern matched variables,
  // which enables to fail pattern matching if the variables with the same name
  // are being pattern matched to different values.
  //
  // right param is before left param, because we need the right arg evaluated before left arg.
  static matchOperator(right, left, vars, rootMatch = true) {
    if (!vars.__matched__) {
      vars.__matched__ = {};
    }

    if (Interpreter.#hasUnresolvedVariablePattern(right)) {
      return {type: "match_pattern", left: left, right: right};
    }

    if (left.type === "match_pattern") {
      Interpreter.matchOperator(right, left.right, vars, false);
      return Interpreter.matchOperator(right, left.left, vars, false);
    }

    if (Type.isMatchPlaceholder(left)) {
      return Interpreter.#handleMatchResult(right, vars, rootMatch);
    }

    if (Type.isVariablePattern(left)) {
      return Interpreter.#matchVariablePattern(right, left, vars, rootMatch);
    }

    if (Type.isConsPattern(left)) {
      return Interpreter.#matchConsPattern(right, left, vars, rootMatch);
    }

    if (Type.isBitstringPattern(left)) {
      return Interpreter.#matchBitstringPattern(right, left, vars, rootMatch);
    }

    if (left.type !== right.type) {
      throw new HologramMatchError(right);
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter.#matchListOrTuple(right, left, vars, rootMatch);
    }

    if (Type.isMap(left)) {
      return Interpreter.#matchMap(right, left, vars, rootMatch);
    }

    if (!Interpreter.isStrictlyEqual(left, right)) {
      throw new HologramMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static module(alias) {
    return globalThis[Interpreter.moduleName(alias)];
  }

  static moduleName(alias) {
    const aliasStr = Type.isAtom(alias) ? alias.value : alias;
    let prefixedAliasStr;

    if (aliasStr === "erlang") {
      prefixedAliasStr = "Erlang";
    } else {
      prefixedAliasStr =
        aliasStr.charAt(0).toLowerCase() === aliasStr.charAt(0)
          ? "Erlang_" + aliasStr
          : aliasStr;
    }

    return prefixedAliasStr.replace(/\./g, "_");
  }

  static raiseArgumentError(message) {
    return Interpreter.raiseError("ArgumentError", message);
  }

  static raiseBadMapError(message) {
    return Interpreter.raiseError("BadMapError", message);
  }

  static raiseCompileError(message) {
    return Interpreter.raiseError("CompileError", message);
  }

  static raiseError(aliasStr, message) {
    const errorStruct = Type.errorStruct(aliasStr, message);
    return Erlang["error/1"](errorStruct);
  }

  static raiseKeyError(message) {
    return Interpreter.raiseError("KeyError", message);
  }

  static raiseMatchError(right) {
    const message =
      "no match of right hand side value: " + Interpreter.inspect(right);

    return Interpreter.raiseError("MatchError", message);
  }

  static serialize(term) {
    return JSON.stringify(term, (_key, value) =>
      typeof value === "bigint" ? `__bigint__:${value.toString()}` : value,
    );
  }

  static takeVarsSnapshot(vars) {
    vars.__snapshot__ = Interpreter.cloneVars(vars);
  }

  // TODO: implement
  static try() {
    throw new Error("try syntax is not yet implemented");
  }

  static #evaluateGuards(guards, vars) {
    if (guards.length === 0) {
      return true;
    }

    for (const guard of guards) {
      if (Type.isTrue(guard(vars))) {
        return true;
      }
    }

    return false;
  }

  static #handleMatchResult(result, vars, rootMatch) {
    if (rootMatch) {
      delete vars.__matched__;
    }

    return result;
  }

  static #hasUnresolvedVariablePattern(term) {
    if (
      [
        "anonymous_function",
        "atom",
        "bitstring",
        "float",
        "integer",
        "match_placeholder",
      ].includes(term.type)
    ) {
      return false;
    }

    if (term.type === "variable_pattern") {
      return true;
    }

    if (term.type === "cons_pattern") {
      return (
        Interpreter.#hasUnresolvedVariablePattern(term.head) ||
        Interpreter.#hasUnresolvedVariablePattern(term.tail)
      );
    }

    if (term.type === "list" || term.type === "tuple") {
      return term.data.some((item) =>
        Interpreter.#hasUnresolvedVariablePattern(item),
      );
    }

    if (term.type === "map") {
      for (const [key, value] of Object.values(term.data)) {
        if (
          Interpreter.#hasUnresolvedVariablePattern(key) ||
          Interpreter.#hasUnresolvedVariablePattern(value)
        ) {
          return true;
        }
      }
    }

    if (term.type === "match_pattern") {
      return (
        Interpreter.#hasUnresolvedVariablePattern(term.left) ||
        Interpreter.#hasUnresolvedVariablePattern(term.right)
      );
    }

    return false;
  }

  static #matchBitstringPattern(right, left, vars, rootMatch) {
    let offset = 0;

    for (const segment of left.segments) {
      if (segment.value.type === "variable_pattern") {
        // TODO: implement
      } else {
        const segmentBitstring = Type.bitstring([segment]);
        const segmentLen = segmentBitstring.bits.length;

        if (right.bits.length - offset < segmentLen) {
          throw new HologramMatchError(right);
        }

        for (let i = 0; i < segmentLen; ++i) {
          if (segmentBitstring.bits[i] !== right.bits[offset + i]) {
            throw new HologramMatchError(right);
          }
        }

        offset += segmentLen;
      }
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchConsPattern(right, left, vars, rootMatch) {
    if (!Type.isList(right) || right.data.length === 0) {
      throw new HologramMatchError(right);
    }

    if (
      Type.isList(left.tail) &&
      Type.isProperList(left.tail) !== Type.isProperList(right)
    ) {
      throw new HologramMatchError(right);
    }

    const rightHead = Erlang["hd/1"](right);
    const rightTail = Erlang["tl/1"](right);

    if (
      !Interpreter.isMatched(left.head, rightHead, vars, false) ||
      !Interpreter.isMatched(left.tail, rightTail, vars, false)
    ) {
      throw new HologramMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchListOrTuple(right, left, vars, rootMatch) {
    const count = left.data.length;

    try {
      if (left.data.length !== right.data.length) {
        throw new HologramMatchError(right);
      }

      if (Type.isList(left) && left.isProper !== right.isProper) {
        throw new HologramMatchError(right);
      }

      for (let i = 0; i < count; ++i) {
        Interpreter.matchOperator(right.data[i], left.data[i], vars, false);
      }
    } catch {
      throw new HologramMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchMap(right, left, vars, rootMatch) {
    try {
      for (const [key, value] of Object.entries(left.data)) {
        Interpreter.matchOperator(right.data[key][1], value[1], vars, false);
      }
    } catch {
      throw new HologramMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchVariablePattern(right, left, vars, rootMatch) {
    if (vars.__matched__[left.name]) {
      if (!Interpreter.isStrictlyEqual(vars.__matched__[left.name], right)) {
        throw new HologramMatchError(right);
      }
    } else {
      vars[left.name] = right;
      vars.__matched__[left.name] = right;
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #raiseCaseClauseError(message) {
    return Interpreter.raiseError("CaseClauseError", message);
  }

  static #raiseCondClauseError() {
    return Interpreter.raiseError(
      "CondClauseError",
      "no cond clause evaluated to a truthy value",
    );
  }

  static #raiseFunctionClauseError(message) {
    return Interpreter.raiseError("FunctionClauseError", message);
  }

  static #raiseUndefinedFunctionError(moduleName, functionName, arity) {
    // TODO: include info about available alternative arities
    const inspectedModuleName = Interpreter.inspectModuleName(moduleName);
    const message = `function ${inspectedModuleName}.${functionName}/${arity} is undefined or private`;

    return Interpreter.raiseError("UndefinedFunctionError", message);
  }
}

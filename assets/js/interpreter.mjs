"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep.js";
import isEqual from "lodash/isEqual.js";
import uniqWith from "lodash/uniqWith.js";

import Bitstring from "./bitstring.mjs";
import Console from "./console.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramMatchError from "./errors/match_error.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Interpreter {
  static accessKeywordListElement(keywordList, key) {
    const keyfindRes = Erlang_Lists["keyfind/3"](
      key,
      Type.integer(1),
      keywordList,
    );

    return Type.isTuple(keyfindRes) ? keyfindRes.data[1] : null;
  }

  // TODO: Remove when structural comparison is fully implemented.
  // See: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // and :erlang.</2, :erlang.>/2 and similar
  static assertStructuralComparisonSupportedType(term) {
    if (!Type.isAtom(term) && !Type.isFloat(term) && !Type.isInteger(term)) {
      const message = `Structural comparison currently supports only atoms, floats and integers, got: ${Interpreter.inspect(
        term,
      )}`;

      throw new HologramInterpreterError(message);
    }
  }

  static buildErrorsFoundMsg(argumentIndex, message) {
    // Based on: https://stackoverflow.com/a/39466341/13040586
    const suffix =
      ["st", "nd", "rd"][((((argumentIndex + 90) % 100) - 10) % 10) - 1] ||
      "th";

    return `errors were found at the given arguments:\n\n  * ${argumentIndex}${suffix} argument: ${message}\n`;
  }

  static callAnonymousFunction(fun, argsArray) {
    const args = Type.list(argsArray);

    for (const clause of fun.clauses) {
      const varsClone = Interpreter.cloneVars(fun.vars);
      const pattern = Type.list(clause.params(varsClone));

      if (Interpreter.isMatched(pattern, args, varsClone)) {
        Interpreter.updateVarsToMatchedValues(varsClone);

        if (Interpreter.#evaluateGuards(clause.guards, varsClone)) {
          return clause.body(varsClone);
        }
      }
    }

    // TODO: include parent module and function info, once context for error reporting is implemented.
    const message = "no function clause matching in anonymous fn/" + fun.arity;
    return Interpreter.raiseFunctionClauseError(message);
  }

  static callNamedFunction(alias, functionArityStr, args) {
    return Interpreter.moduleRef(alias)[functionArityStr](...args);
  }

  static case(condition, clauses, vars) {
    let conditionVars;

    if (typeof condition === "function") {
      conditionVars = Interpreter.cloneVars(vars);
      condition = condition(conditionVars);
    } else {
      conditionVars = vars;
    }

    for (const clause of clauses) {
      const varsClone = Interpreter.cloneVars(conditionVars);

      if (Interpreter.isMatched(clause.match, condition, varsClone)) {
        Interpreter.updateVarsToMatchedValues(varsClone);

        if (Interpreter.#evaluateGuards(clause.guards, varsClone)) {
          return clause.body(varsClone);
        }
      }
    }

    return Interpreter.raiseCaseClauseError(condition);
  }

  static cloneVars(vars) {
    return cloneDeep(vars);
  }

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  static compareTerms(term1, term2) {
    Interpreter.assertStructuralComparisonSupportedType(term1);
    Interpreter.assertStructuralComparisonSupportedType(term2);

    const term1TypeOrder = Interpreter.getStructuralComparisonTypeOrder(term1);
    const term2TypeOrder = Interpreter.getStructuralComparisonTypeOrder(term2);

    if (term1TypeOrder !== term2TypeOrder) {
      return term1TypeOrder < term2TypeOrder ? -1 : 1;
    }

    switch (term1.type) {
      case "atom":
      case "float":
      case "integer":
        return term1.value == term2.value
          ? 0
          : term1.value < term2.value
            ? -1
            : 1;
    }
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
          Interpreter.isMatched(generators[i].match, combination[i], varsClone)
        ) {
          Interpreter.updateVarsToMatchedValues(varsClone);

          if (Interpreter.#evaluateGuards(generators[i].guards, varsClone)) {
            continue;
          }
        }

        return acc;
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
      globalThis[moduleName] = new Proxy(
        {},
        {
          get(module, fun) {
            if (fun in module) return module[fun];

            const message = `Function ${Interpreter.inspectModuleName(
              moduleName,
            )}.${fun} is not available on the client. See what to do here: https://www.hologram.page/TODO`;

            throw new HologramInterpreterError(message);
          },
        },
      );

      globalThis[moduleName].__hologramJsModuleName__ = moduleName;
    }

    globalThis[moduleName][`${functionName}/${functionArity}`] = function () {
      const mfa = `${Interpreter.inspectModuleName(
        moduleName,
      )}.${functionName}/${functionArity}`;

      // TODO: remove on release
      // Interpreter.#logFunctionCall(mfa, arguments);

      const args = Type.list([...arguments]);

      for (const clause of clauses) {
        const vars = {};
        const pattern = Type.list(clause.params(vars));

        if (Interpreter.isMatched(pattern, args, vars)) {
          Interpreter.updateVarsToMatchedValues(vars);

          if (Interpreter.#evaluateGuards(clause.guards, vars)) {
            const result = clause.body(vars);

            // TODO: remove on release
            // Interpreter.#logFunctionResult(mfa, result);

            return result;
          }
        }
      }

      const message = `no function clause matching in ${mfa}`;
      Interpreter.raiseFunctionClauseError(message);
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
      return Interpreter.moduleRef(left)[functionArityStr]();
    }

    // otherwise treat the operator as map key access
    return Erlang_Maps["get/2"](right, left);
  }

  static fetchErrorMessage(jsError) {
    // TODO: use transpiled Elixir code
    return Bitstring.toText(jsError.struct.data["atom(message)"][1]);
  }

  static fetchErrorType(jsError) {
    // TODO: use transpiled Elixir code
    return jsError.struct.data["atom(__struct__)"][1].value.substring(7);
  }

  // See type ordering spec: https://hexdocs.pm/elixir/main/Kernel.html#module-term-ordering
  static getStructuralComparisonTypeOrder(term) {
    switch (term.type) {
      case "anonymous_function":
        return 4;

      case "atom":
        return 2;

      case "bitstring":
        return 10;

      case "float":
      case "integer":
        return 1;

      case "list":
        return 9;

      case "map":
        return 8;

      case "pid":
        return 6;

      case "port":
        return 5;

      case "reference":
        return 3;

      case "tuple":
        return 7;
    }
  }

  // Important: keep Kernel.inspect/2 consistency tests in sync.
  // TODO: finish (e.g. implement text detection in binaries and other types such as pid, etc.)
  static inspect(term, opts = {}) {
    switch (term.type) {
      case "atom":
        return Interpreter.#inspectAtom(term, opts);

      case "bitstring":
        return Interpreter.#inspectBitstring(term, opts);

      case "float":
        return Interpreter.#inspectFloat(term, opts);

      case "integer":
        return term.value.toString();

      case "list":
        return Interpreter.#inspectList(term, opts);

      case "map":
        return Interpreter.#inspectMap(term, opts);

      case "string":
        return `"${term.value}"`;

      case "tuple":
        return Interpreter.#inspectTuple(term, opts);

      // TODO: remove when all types are supported
      default:
        return Interpreter.serialize(term);
    }
  }

  static inspectModuleName(moduleName) {
    if (moduleName.startsWith("Elixir_")) {
      return moduleName.slice(7).replaceAll("_", ".");
    }

    if (moduleName === "Erlang") {
      return ":erlang";
    }

    // starts with "Erlang_"
    return ":" + moduleName.slice(7).toLowerCase();
  }

  static isEqual(left, right) {
    if (Type.isNumber(left)) {
      if (Type.isNumber(right)) {
        return left.value == right.value;
      } else {
        return false;
      }
    }

    return isEqual(left, right);
  }

  static isMatched(left, right, vars) {
    try {
      Interpreter.matchOperator(right, left, vars);
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
  // are being pattern matched to different values
  // and to update the var values after pattern matching is finished.
  //
  // right param is before left param, because we need the right arg evaluated before left arg.
  static matchOperator(right, left, vars) {
    if (!vars.__matched__) {
      vars.__matched__ = {};
    }

    if (Interpreter.#hasUnresolvedVariablePattern(right)) {
      return {type: "match_pattern", left: left, right: right};
    }

    if (left.type === "match_pattern") {
      Interpreter.matchOperator(right, left.right, vars);
      return Interpreter.matchOperator(right, left.left, vars);
    }

    if (Type.isMatchPlaceholder(left)) {
      return right;
    }

    if (Type.isVariablePattern(left)) {
      return Interpreter.#matchVariablePattern(right, left, vars);
    }

    if (Type.isConsPattern(left)) {
      return Interpreter.#matchConsPattern(right, left, vars);
    }

    if (Type.isBitstringPattern(left)) {
      return Interpreter.#matchBitstringPattern(right, left, vars);
    }

    if (left.type !== right.type) {
      throw new HologramMatchError(right);
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter.#matchListOrTuple(right, left, vars);
    }

    if (Type.isMap(left)) {
      return Interpreter.#matchMap(right, left, vars);
    }

    if (!Interpreter.isStrictlyEqual(left, right)) {
      throw new HologramMatchError(right);
    }

    return right;
  }

  // Based on: Hologram.Compiler.Encoder.encode_as_class_name/1
  static moduleName(alias) {
    const aliasStr = Type.isAtom(alias) ? alias.value : alias;

    if (aliasStr === "erlang") {
      return "Erlang";
    }

    let segments = aliasStr.split(/[._]/);

    if (segments[0] !== "Elixir") {
      segments.unshift("Erlang");
    }

    return segments.map((segment) => Utils.capitalize(segment)).join("_");
  }

  static moduleRef(alias) {
    return globalThis[Interpreter.moduleName(alias)];
  }

  static raiseArgumentError(message) {
    return Interpreter.raiseError("ArgumentError", message);
  }

  static raiseArithmeticError() {
    return Interpreter.raiseError(
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  }

  static raiseBadMapError(arg) {
    const message = "expected a map, got: " + Interpreter.inspect(arg);

    return Interpreter.raiseError("BadMapError", message);
  }

  static raiseCaseClauseError(arg) {
    const message = "no case clause matching: " + Interpreter.inspect(arg);

    return Interpreter.raiseError("CaseClauseError", message);
  }

  static raiseCompileError(message) {
    return Interpreter.raiseError("CompileError", message);
  }

  static raiseError(aliasStr, message) {
    const errorStruct = Type.errorStruct(aliasStr, message);
    return Erlang["error/1"](errorStruct);
  }

  static raiseFunctionClauseError(message) {
    return Interpreter.raiseError("FunctionClauseError", message);
  }

  static raiseKeyError(message) {
    return Interpreter.raiseError("KeyError", message);
  }

  static raiseMatchError(arg) {
    const message =
      "no match of right hand side value: " + Interpreter.inspect(arg);

    return Interpreter.raiseError("MatchError", message);
  }

  static serialize(term) {
    return JSON.stringify(term, (_key, value) =>
      typeof value === "bigint" ? `__bigint__:${value.toString()}` : value,
    );
  }

  static try(body, rescueClauses, catchClauses, elseClauses, afterBlock, vars) {
    let result;

    try {
      const varsClone = Interpreter.cloneVars(vars);
      result = body(varsClone);
      // TODO: finish
      // eslint-disable-next-line no-useless-catch
    } catch (error) {
      throw error;

      // TODO: handle errors
      // eslint-disable-next-line no-unreachable
      result =
        Interpreter.#evaluateRescueClauses(rescueClauses, error, vars) ||
        Interpreter.#evaluateCatchClauses(catchClauses, error, vars);
    } finally {
      // TODO: handle after block
      if (afterBlock) {
        // eslint-disable-next-line no-unsafe-finally
        throw new Error(
          '"try" expression after block is not yet implemented in Hologram',
        );
      }
    }

    if (elseClauses.length === 0) {
      return result;
    } else {
      // TODO: handle else clauses
      throw new Error(
        '"try" expression else clauses are not yet implemented in Hologram',
      );
    }
  }

  static updateVarsToMatchedValues(vars) {
    Object.assign(vars, vars.__matched__);
    delete vars.__matched__;

    return vars;
  }

  // TODO: finish implementing
  static with() {
    throw new Error('"with" expression is not yet implemented in Hologram');
  }

  static #evaluateCatchClauses(clauses, error, vars) {
    for (const clause of clauses) {
      const varsClone = Interpreter.cloneVars(vars);

      if (Interpreter.#matchCatchClause(clause, error, varsClone)) {
        return clause.body(varsClone);
      }
    }

    return false;
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

  static #evaluateRescueClauses(clauses, error, vars) {
    for (const clause of clauses) {
      const varsClone = Interpreter.cloneVars(vars);

      if (Interpreter.#matchRescueClause(clause, error, varsClone)) {
        return clause.body(varsClone);
      }
    }

    return false;
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

  // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
  static #inspectAtom(term, _opts) {
    if (Type.isBoolean(term) || Type.isNil(term)) {
      return term.value;
    }

    if (Type.isAlias(term)) {
      return term.value.slice(7);
    }

    return ":" + term.value;
  }

  // TODO: support bitstrings which are not text
  static #inspectBitstring(term, _opts) {
    if (Bitstring.isText(term)) {
      return '"' + Bitstring.toText(term) + '"';
    }

    // TODO: this is temporary
    return `bitstring(${term.bits.length})`;
  }

  static #inspectFloat(term, _opts) {
    if (Number.isInteger(term.value)) {
      return term.value.toString() + ".0";
    }

    return term.value.toString();
  }

  // TODO: support keyword lists
  static #inspectList(term, opts) {
    if (term.isProper) {
      return (
        "[" +
        term.data.map((elem) => Interpreter.inspect(elem, opts)).join(", ") +
        "]"
      );
    }

    return (
      "[" +
      term.data
        .slice(0, -1)
        .map((elem) => Interpreter.inspect(elem, opts))
        .join(", ") +
      " | " +
      Interpreter.inspect(term.data.slice(-1)[0]) +
      "]"
    );
  }

  static #inspectMap(term, opts) {
    const isAtomKeyMap = Object.values(term.data).every(([key, _value]) =>
      Type.isAtom(key),
    );

    let itemsStr = "";

    if (isAtomKeyMap) {
      itemsStr = Object.values(term.data)
        .map(
          ([key, value]) => `${key.value}: ${Interpreter.inspect(value, opts)}`,
        )
        .join(", ");
    } else {
      itemsStr = Object.values(term.data)
        .map(
          ([key, value]) =>
            `${Interpreter.inspect(key, opts)} => ${Interpreter.inspect(
              value,
              opts,
            )}`,
        )
        .join(", ");
    }

    return "%{" + itemsStr + "}";
  }

  static #inspectTuple(term, opts) {
    return (
      "{" +
      term.data.map((elem) => Interpreter.inspect(elem, opts)).join(", ") +
      "}"
    );
  }

  static #logFunctionCall(mfa, args) {
    Console.startGroup(mfa);

    if (args.length > 0) {
      Console.printHeader("args");

      for (let i = 0; i < args.length; ++i) {
        Console.printDataItem(i + 1, args[i]);
      }
    }
  }

  static #logFunctionResult(mfa, result) {
    Console.printHeader("result");
    Console.printData(result);
    Console.endGroup(mfa);
  }

  static #matchBitstringPattern(right, left, vars) {
    if (right.type !== "bitstring" && right.type !== "bitstring_pattern") {
      throw new HologramMatchError(right);
    }

    let offset = 0;

    for (const segment of left.segments) {
      if (segment.value.type === "variable_pattern") {
        const valueInfo = Bitstring.buildValueFromBitstringChunk(
          segment,
          right.bits,
          offset,
        );

        if (!valueInfo) {
          throw new HologramMatchError(right);
        }

        const [value, segmentLen] = valueInfo;
        Interpreter.matchOperator(value, segment.value, vars);
        offset += segmentLen;
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

    if (offset < right.bits.length) {
      throw new HologramMatchError(right);
    }

    return right;
  }

  static #matchCatchClause(_clause, _error, _vars) {
    // TODO: handle catch clauses
    throw new Error(
      '"try" expression catch clauses are not yet implemented in Hologram',
    );
  }

  static #matchConsPattern(right, left, vars) {
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
      !Interpreter.isMatched(left.head, rightHead, vars) ||
      !Interpreter.isMatched(left.tail, rightTail, vars)
    ) {
      throw new HologramMatchError(right);
    }

    return right;
  }

  static #matchListOrTuple(right, left, vars) {
    const count = left.data.length;

    if (left.data.length !== right.data.length) {
      throw new HologramMatchError(right);
    }

    if (Type.isList(left) && left.isProper !== right.isProper) {
      throw new HologramMatchError(right);
    }

    for (let i = 0; i < count; ++i) {
      if (!Interpreter.isMatched(left.data[i], right.data[i], vars)) {
        throw new HologramMatchError(right);
      }
    }

    return right;
  }

  static #matchMap(right, left, vars) {
    for (const [key, value] of Object.entries(left.data)) {
      if (
        typeof right.data[key] === "undefined" ||
        !Interpreter.isMatched(value[1], right.data[key][1], vars)
      ) {
        throw new HologramMatchError(right);
      }
    }

    return right;
  }

  static #matchRescueClause(_clause, _error, _vars) {
    // TODO: handle rescue clauses
    throw new Error(
      '"try" expression rescue clauses are not yet implemented in Hologram',
    );
  }

  static #matchVariablePattern(right, left, vars) {
    if (vars.__matched__[left.name]) {
      if (!Interpreter.isStrictlyEqual(vars.__matched__[left.name], right)) {
        throw new HologramMatchError(right);
      }
    } else {
      vars.__matched__[left.name] = right;
    }

    return right;
  }

  static #raiseCondClauseError() {
    return Interpreter.raiseError(
      "CondClauseError",
      "no cond clause evaluated to a truthy value",
    );
  }
}

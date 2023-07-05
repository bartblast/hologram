"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual.js";
import uniqWith from "lodash/uniqWith.js";

import Hologram from "./hologram.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Interpreter {
  static callAnonymousFunction(fun, argsArray) {
    const args = Type.list(argsArray);

    for (const clause of fun.clauses) {
      const varsClone = Utils.clone(fun.vars);
      const pattern = Type.list(clause.params);

      try {
        if (
          Interpreter.matchOperator(args, pattern, varsClone) &&
          Interpreter.#evaluateGuard(clause.guard, varsClone)
        ) {
          return clause.body(varsClone);
        }
      } catch {}
    }

    // TODO: include parent module and function info, once context for error reporting is implemented.
    const message = "no function clause matching in anonymous fn/" + fun.arity;
    return Interpreter.#raiseFunctionClauseError(message);
  }

  static case(condition, clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Utils.clone(vars);

      try {
        Interpreter.matchOperator(condition, clause.head, varsClone);

        if (Interpreter.#evaluateGuard(clause.guard, varsClone) === false) {
          continue;
        }
        return clause.body(varsClone);
      } catch {
        continue;
      }
    }

    const message = "no case clause matching: " + Hologram.inspect(condition);

    return Interpreter.#raiseCaseClauseError(message);
  }

  static comprehension(generators, filters, collectable, unique, mapper, vars) {
    const generatorsCount = generators.length;

    const sets = generators.map(
      (generator) => Elixir_Enum.to_list(generator.enumerable).data
    );

    let items = Utils.cartesianProduct(sets).reduce((acc, combination) => {
      const varsClone = Utils.clone(vars);

      for (let i = 0; i < generatorsCount; ++i) {
        try {
          Interpreter.matchOperator(
            combination[i],
            generators[i].match,
            varsClone
          );

          if (
            Interpreter.#evaluateGuard(generators[i].guard, varsClone) === false
          ) {
            return acc;
          }
        } catch {
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

    return Elixir_Enum.into(Type.list(items), collectable);
  }

  static cond(clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Utils.clone(vars);

      if (Type.isTruthy(clause.condition(varsClone))) {
        return clause.body(varsClone);
      }
    }

    return Interpreter.#raiseCondClauseError();
  }

  static consOperator(left, right) {
    return Type.list([left].concat(right.data));
  }

  static defineFunction(moduleName, functionName, clauses) {
    if (!globalThis[moduleName]) {
      globalThis[moduleName] = {};
    }

    globalThis[moduleName][functionName] = function () {
      const args = Type.list(arguments);
      const arity = arguments.length;

      if (!Interpreter.#isArityDefined(clauses, arity)) {
        Interpreter.#raiseUndefinedFunctionError(
          moduleName,
          functionName,
          arity
        );
      }

      for (const clause of clauses) {
        const vars = {};
        const pattern = Type.list(clause.params);

        try {
          Interpreter.matchOperator(args, pattern, vars);

          if (Interpreter.#evaluateGuard(clause.guard, vars)) {
            return clause.body(vars);
          }
        } catch {}
      }

      const inspectedModuleName = Hologram.inspectModuleName(moduleName);
      const message = `no function clause matching in ${inspectedModuleName}.${functionName}/${arity}`;
      Interpreter.#raiseFunctionClauseError(message);
    };
  }

  static dotOperator(left, right) {
    // if left argument is a boxed atom, treat the operator as a remote function call
    if (Type.isAtom(left)) {
      return Hologram.module(left)[right.value]();
    }

    // otherwise treat the operator as map key access
    return Erlang_maps.get(right, left);
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

    if (left.type !== right.type) {
      Interpreter.raiseMatchError(right);
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter.#matchListOrTuple(right, left, vars, rootMatch);
    }

    if (Type.isMap(left)) {
      return Interpreter.#matchMap(right, left, vars, rootMatch);
    }

    if (!Interpreter.isStrictlyEqual(left, right)) {
      Interpreter.raiseMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static raiseMatchError(right) {
    const message =
      "no match of right hand side value: " + Hologram.inspect(right);

    return Hologram.raiseError("MatchError", message);
  }

  static takeVarsSnapshot(vars) {
    delete vars.__snapshot__;
    vars.__snapshot__ = Utils.clone(vars);
  }

  static #evaluateGuard(guard, vars) {
    if (guard === null) {
      return true;
    }

    return Type.isTrue(guard(vars));
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
        Interpreter.#hasUnresolvedVariablePattern(item)
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

    return false;
  }

  static #isArityDefined(clauses, arity) {
    return clauses.some((clause) => clause.params.length === arity);
  }

  static #matchConsPattern(right, left, vars, rootMatch) {
    if (!Type.isList(right) || Erlang.length(right).value === 0n) {
      Interpreter.raiseMatchError(right);
    }

    const rightHead = Erlang.hd(right);
    const rightTail = Erlang.tl(right);

    try {
      Interpreter.matchOperator(rightHead, left.head, vars, false);
      Interpreter.matchOperator(rightTail, left.tail, vars, false);
    } catch {
      Interpreter.raiseMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchListOrTuple(right, left, vars, rootMatch) {
    const count = Elixir_Enum.count(left).value;

    try {
      for (let i = 0; i < count; ++i) {
        Interpreter.matchOperator(right.data[i], left.data[i], vars, false);
      }
    } catch {
      Interpreter.raiseMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchMap(right, left, vars, rootMatch) {
    try {
      for (const [key, value] of Object.entries(left.data)) {
        Interpreter.matchOperator(right.data[key][1], value[1], vars, false);
      }
    } catch {
      Interpreter.raiseMatchError(right);
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #matchVariablePattern(right, left, vars, rootMatch) {
    if (vars.__matched__[left.name]) {
      if (!Interpreter.isStrictlyEqual(vars.__matched__[left.name], right)) {
        Interpreter.raiseMatchError(right);
      }
    } else {
      vars[left.name] = right;
      vars.__matched__[left.name] = right;
    }

    return Interpreter.#handleMatchResult(right, vars, rootMatch);
  }

  static #raiseCaseClauseError(message) {
    return Hologram.raiseError("CaseClauseError", message);
  }

  static #raiseCondClauseError() {
    return Hologram.raiseError(
      "CondClauseError",
      "no cond clause evaluated to a truthy value"
    );
  }

  static #raiseFunctionClauseError(message) {
    return Hologram.raiseError("FunctionClauseError", message);
  }

  static #raiseUndefinedFunctionError(moduleName, functionName, arity) {
    // TODO: include info about available alternative arities
    const inspectedModuleName = Hologram.inspectModuleName(moduleName);
    const message = `function ${inspectedModuleName}.${functionName}/${arity} is undefined or private`;

    return Hologram.raiseError("UndefinedFunctionError", message);
  }
}

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

      if (
        Interpreter.isMatched(pattern, args) &&
        Interpreter.matchOperator(pattern, args, varsClone, false) &&
        Interpreter.#evaluateGuard(clause.guard, varsClone)
      ) {
        return clause.body(varsClone);
      }
    }

    // TODO: include parent module and function info, once context for error reporting is implemented.
    const message = "no function clause matching in anonymous fn/" + fun.arity;
    return Interpreter.#raiseFunctionClauseError(message);
  }

  static case(condition, clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Utils.clone(vars);

      if (Interpreter.isMatched(clause.head, condition)) {
        Interpreter.matchOperator(clause.head, condition, varsClone, false);

        if (Interpreter.#evaluateGuard(clause.guard, varsClone) === false) {
          continue;
        }
        return clause.body(varsClone);
      } else {
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
        if (Interpreter.isMatched(generators[i].match, combination[i])) {
          Interpreter.matchOperator(
            generators[i].match,
            combination[i],
            varsClone,
            false
          );

          if (
            Interpreter.#evaluateGuard(generators[i].guard, varsClone) === false
          ) {
            return acc;
          }
        } else {
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

        if (
          Interpreter.isMatched(pattern, args) &&
          Interpreter.matchOperator(pattern, args, vars, false) &&
          Interpreter.#evaluateGuard(clause.guard, vars)
        ) {
          return clause.body(vars);
        }
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

  // static isMatched(left, right) {
  //   if (Type.isVariablePattern(left) || Type.isMatchPlaceholder(left)) {
  //     return true;
  //   }

  //   if (Type.isConsPattern(left)) {
  //     return Interpreter.#isConsPatternMatched(left, right);
  //   }

  //   if (left.type !== right.type) {
  //     return false;
  //   }

  //   if (Type.isList(left) || Type.isTuple(left)) {
  //     return Interpreter.#isListOrTupleMatched(left, right);
  //   }

  //   if (Type.isMap(left)) {
  //     return Interpreter.#isMapMatched(left, right);
  //   }

  //   return Interpreter.isStrictlyEqual(left, right);
  // }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  // static matchOperator(left, right, vars, assertMatches = true) {
  //   if (assertMatches && !Interpreter.isMatched(left, right)) {
  //     Interpreter.#raiseMatchError(right);
  //   } else if (Type.isVariablePattern(left)) {
  //     vars[left.name] = right;
  //   } else if (Type.isMatchPlaceholder(left)) {
  //     // do nothing
  //   } else if (Type.isConsPattern(left, right)) {
  //     Interpreter.#matchConsPattern(left, right, vars);
  //   } else if (Type.isList(left) || Type.isTuple(left)) {
  //     Interpreter.#matchListOrTuple(left, right, vars);
  //   } else if (Type.isMap(left)) {
  //     Interpreter.#matchMap(left, right, vars);
  //   }

  //   return right;
  // }

  static #evaluateGuard(guard, vars) {
    if (guard === null) {
      return true;
    }

    return Type.isTrue(guard(vars));
  }

  static #isArityDefined(clauses, arity) {
    return clauses.some((clause) => clause.params.length === arity);
  }

  static #isConsPatternMatched(left, right) {
    if (!Type.isList(right) || Erlang.length(right).value === 0n) {
      return false;
    }

    const rightHead = Erlang.hd(right);
    const rightTail = Erlang.tl(right);

    return (
      Interpreter.isMatched(left.head, rightHead) &&
      Interpreter.isMatched(left.tail, rightTail)
    );
  }

  static #isListOrTupleMatched(left, right) {
    const count = Elixir_Enum.count(left).value;

    if (count !== Elixir_Enum.count(right).value) {
      return false;
    }

    for (let i = 0; i < count; ++i) {
      if (!Interpreter.isMatched(left.data[i], right.data[i])) {
        return false;
      }
    }

    return true;
  }

  static #isMapMatched(left, right) {
    for (const [key, value] of Object.entries(left.data)) {
      if (
        !(key in right.data) ||
        !Interpreter.isMatched(value[1], right.data[key][1])
      ) {
        return false;
      }
    }

    return true;
  }

  static #matchConsPattern(left, right, vars) {
    const rightHead = Erlang.hd(right);
    const rightTail = Erlang.tl(right);

    Interpreter.matchOperator(left.head, rightHead, vars, false);
    Interpreter.matchOperator(left.tail, rightTail, vars, false);
  }

  static #matchListOrTuple(left, right, vars) {
    const count = Elixir_Enum.count(left).value;

    for (let i = 0; i < count; ++i) {
      Interpreter.matchOperator(left.data[i], right.data[i], vars, false);
    }
  }

  static #matchMap(left, right, vars) {
    for (const [key, value] of Object.entries(left.data)) {
      Interpreter.matchOperator(value[1], right.data[key][1], vars, false);
    }
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

  static #raiseMatchError(right) {
    const message =
      "no match of right hand side value: " + Hologram.inspect(right);

    return Hologram.raiseError("MatchError", message);
  }

  static #raiseUndefinedFunctionError(moduleName, functionName, arity) {
    // TODO: include info about available alternative arities
    const inspectedModuleName = Hologram.inspectModuleName(moduleName);
    const message = `function ${inspectedModuleName}.${functionName}/${arity} is undefined or private`;

    return Hologram.raiseError("UndefinedFunctionError", message);
  }
}

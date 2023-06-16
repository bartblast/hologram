"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual.js";
import uniqWith from "lodash/uniqWith.js";

import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class Interpreter {
  static _moduleEnum;

  static callAnonymousFunction(fun, args) {
    const right = Type.list(args);

    for (const clause of fun.clauses) {
      const varsClone = Utils.clone(fun.vars);
      const left = Type.list(clause.params);

      if (
        Interpreter.isMatched(left, right) &&
        Interpreter.matchOperator(left, right, varsClone, false) &&
        Interpreter._evaluateGuard(clause.guard, varsClone)
      ) {
        return clause.body(varsClone);
      }
    }

    // TODO: Include module and function info, once context for error reporting is implemented.
    const message = "no function clause matching in anonymous fn/" + fun.arity;
    return Interpreter.raiseFunctionClauseError(message);
  }

  static case(condition, clauses, vars) {
    for (const clause of clauses) {
      const varsClone = Utils.clone(vars);

      if (Interpreter.isMatched(clause.head, condition)) {
        Interpreter.matchOperator(clause.head, condition, varsClone, false);

        if (Interpreter._evaluateGuard(clause.guard, varsClone) === false) {
          continue;
        }
        return clause.body(varsClone);
      } else {
        continue;
      }
    }

    const message =
      "no case clause matching: " + Interpreter.inspect(condition);

    return Interpreter.raiseCaseClauseError(message);
  }

  static comprehension(generators, filters, collectable, unique, mapper, vars) {
    const generatorsCount = generators.length;

    const sets = generators.map(
      (generator) => Interpreter._moduleEnum.to_list(generator.enumerable).data
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
            Interpreter._evaluateGuard(generators[i].guard, varsClone) === false
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

    return Interpreter._moduleEnum.into(Type.list(items), collectable);
  }

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
      // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
      case "atom":
        if (Type.isBoolean(term) || Type.isNil(term)) {
          return term.value;
        }
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

  static isMatched(left, right) {
    if (Type.isVariablePattern(left) || Type.isMatchPlaceholder(left)) {
      return true;
    }

    if (left.type !== right.type) {
      return false;
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      return Interpreter._isListOrTupleMatched(left, right);
    }

    if (Type.isMap(left)) {
      return Interpreter._isMapMatched(left, right);
    }

    return Interpreter.isStrictlyEqual(left, right);
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  static matchOperator(left, right, vars, assertMatches = true) {
    if (assertMatches && !Interpreter.isMatched(left, right)) {
      Interpreter._raiseMatchError(right);
    }

    if (Type.isVariablePattern(left)) {
      vars[left.name] = right;
      return right;
    }

    if (Type.isMatchPlaceholder(left)) {
      return right;
    }

    if (Type.isList(left) || Type.isTuple(left)) {
      const count = Interpreter.count(left);

      for (let i = 0; i < count; ++i) {
        Interpreter.matchOperator(left.data[i], right.data[i], vars, false);
      }
    }

    if (Type.isMap(left)) {
      for (const [key, value] of Object.entries(left.data)) {
        Interpreter.matchOperator(value[1], right.data[key][1], vars, false);
      }
    }

    return right;
  }

  static raiseCaseClauseError(message) {
    return Interpreter.raiseError("CaseClauseError", message);
  }

  static raiseError(type, message) {
    throw new Error(`(${type}) ${message}`);
  }

  static raiseFunctionClauseError(message) {
    return Interpreter.raiseError("FunctionClauseError", message);
  }

  static raiseNotYetImplementedError(message) {
    return Interpreter.raiseError("Hologram.NotYetImplementedError", message);
  }

  static tail(list) {
    return Type.list(list.data.slice(1));
  }

  // private
  static _evaluateGuard(guard, vars) {
    if (guard === null) {
      return true;
    }

    return Type.isTrue(guard(vars));
  }

  // private
  static _isListOrTupleMatched(left, right) {
    const count = Interpreter.count(left);

    if (count !== Interpreter.count(right)) {
      return false;
    }

    for (let i = 0; i < count; ++i) {
      if (!Interpreter.isMatched(left.data[i], right.data[i])) {
        return false;
      }
    }

    return true;
  }

  // private
  static _isMapMatched(left, right) {
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

  // private
  static _raiseMatchError(right) {
    const message =
      "no match of right hand side value: " + Interpreter.inspect(right);

    return Interpreter.raiseError("MatchError", message);
  }
}

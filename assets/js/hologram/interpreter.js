"use strict";

import { HologramNotImplementedError } from "./errors";
import Enum from "./elixir/enum"
import Map from "./elixir/map"
import Utils from "./utils"

export default class Interpreter {
  static $addition_operator(left, right) {
    const type = left.type === "integer" && right.type === "integer" ? "integer" : "float"
    const result = left.value + right.value
    return Utils.freeze({type: type, value: result})
  }

  static $membership_operator(left, right) {
    return Enum.member$question(right, left)
  }

  static caseExpression(condition, clausesAnonFun) {
    const result = clausesAnonFun(condition)
    return Utils.freeze(result)
  }

  static isFunctionArgsPatternMatched(params, args) {
    if (args.length !== params.length) {
      return false;
    }

    for (let i = 0; i < args.length; ++ i) {
      if (!Interpreter.isPatternMatched(params[i], args[i])) {
        return false;
      }
    }

    return true;
  }

  static isMapPatternMatched(left, right) {
    for (const key of Map.keys(left).data) {
      if (Map.has_key$question(right, key)) {
        if (!Interpreter.isPatternMatched(Map.get(left, key), Map.get(right, key))) {
          return false
        }
      } else {
        return false
      }
    }

    return true 
  }

  static isPatternMatched(left, right) {
    const lType = left.type;
    const rType = right.type;

    if (lType === "placeholder") {
      return true;
    }

    if (lType !== rType) {
      return false;
    }

    switch (lType) {
      case "atom":
      case "integer":
        return left.value === right.value;

      case "map":
        return Interpreter.isMapPatternMatched(left, right)

      case "tuple":
        return Interpreter.isTuplePatternMatched(left, right)

      default:
        const message = `Interpreter.isPatternMatched(): left = ${JSON.stringify(left)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static isTuplePatternMatched(left, right) {
    if (left.data.length !== right.data.length) {
      return false;
    }

    for (let i = 0; i < left.data.length; ++i) {
      if (!Interpreter.isPatternMatched(left.data[i], right.data[i])) {
        return false
      }
    }

    return true
  }
}
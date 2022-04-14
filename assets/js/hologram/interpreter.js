"use strict";

import { HologramNotImplementedError } from "./errors";
import Enum from "./elixir/enum"
import Kernel from "./elixir/kernel"
import List from "./elixir/list";
import Map from "./elixir/map"
import Type from "./type"
import Utils from "./utils"

export default class Interpreter {
  static $addition_operator(left, right) {
    const type = left.type === "integer" && right.type === "integer" ? "integer" : "float"
    const result = left.value + right.value
    return Utils.freeze({type: type, value: result})
  }

  static $cons_operator(head, tail) {
    return List.insert_at(tail, 0, head)
  }

  // TODO: raise ArithmeticError if second argument is 0 or 0.0
  // see: https://github.com/bartblast/hologram/issues/67
  static $division_operator(left, right) {
    const result = Type.float(left.value / right.value)
    return Utils.freeze(result)
  }

  static $dot_operator(left, right) {
    return left.data[Type.encodedKey(right)]
  }

  static $equal_to_operator(left, right) {
    let value;

    switch (left.type) {        
      case "float":
      case "integer":
        value = Interpreter._areNumbersEqual(left, right)
        break;

      default:
        value = left.type === right.type && left.value === right.value
        break;
    }

    return Type.boolean(value)
  }

  static $list_concatenation_operator(left, right) {
    const result = Type.list(left.data.concat(right.data))
    return Utils.freeze(result)
  }

  static $membership_operator(left, right) {
    return Enum.member$question(right, left)
  }

  static $multiplication_operator(left, right) {
    const type = left.type === "integer" && right.type === "integer" ? "integer" : "float"
    const result = left.value * right.value
    return Utils.freeze({type: type, value: result})
  }

  static $not_equal_to_operator(left, right) {
    const isEqualTo = Interpreter.$equal_to_operator(left, right)
    return Type.boolean(!isEqualTo.value)
  }

  static $relaxed_boolean_and_operator(left, right) {
    if (Type.isTruthy(left)) {
      return right
    } else {
      return left
    }
  }

  static caseExpression(condition, clausesAnonFun) {
    const result = clausesAnonFun(condition)
    return Utils.freeze(result)
  }

  static isConsOperatorPatternMatched(left, right) {
    if (right.type !== 'list') {
      return false
    }

    if (right.data.length === 0) {
      return false
    }

    if (!Interpreter.isPatternMatched(left.head, Kernel.hd(right))) {
      return false
    }

    if (!Interpreter.isPatternMatched(left.tail, Kernel.tl(right))) {
      return false
    }

    return true
  }

  static isEnumPatternMatched(left, right) {
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

    if (lType === 'cons_operator_pattern') {
      return Interpreter.isConsOperatorPatternMatched(left, right)
    }

    if (lType !== rType) {
      return false;
    }

    switch (lType) {
      case "atom":
      case "integer":
        return left.value === right.value;

      case "list":
      case "tuple":
        return Interpreter.isEnumPatternMatched(left, right)        

      case "map":
        return Interpreter.isMapPatternMatched(left, right)

      default:
        const message = `Interpreter.isPatternMatched(): left = ${JSON.stringify(left)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static _areNumbersEqual(num1, num2) {
    if (Type.isNumber(num1) && Type.isNumber(num2)) {
      return num1.value == num2.value
    } else {
      return false
    }
  }
}
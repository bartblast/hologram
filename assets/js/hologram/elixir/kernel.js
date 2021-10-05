"use strict";

import HologramNotImplementedError from "../errors";
import Runtime from "../runtime"
import Type from "../type"
import Utils from "../utils"

export default class Kernel {
  static $add(boxedNumber1, boxedNumber2) {
    const type = boxedNumber1.type === "integer" && boxedNumber2.type === "integer" ? "integer" : "float"
    const result = boxedNumber1.value + boxedNumber2.value
    return Utils.freeze({type: type, value: result})
  }

  static apply() {
    if (arguments.length === 3) {
      const module = Runtime.getModule(arguments[0].class_name)
      const functionName = arguments[1].value
      const args = arguments[2].data

      return module[functionName](...args)

    } else {
      const message = `Kernel.apply(): arguments = ${JSON.stringify(arguments)}`
      throw new HologramNotImplementedError(message)
    }
  }

  static _areBoxedNumbersEqual(boxedNumber1, boxedNumber2) {
    if (Type.isNumber(boxedNumber1) && Type.isNumber(boxedNumber2)) {
      return boxedNumber1.value == boxedNumber2.value
    } else {
      return false
    }
  }

  static $dot(boxedMap, boxedKey) {
    return boxedMap.data[Type.mapKey(boxedKey)]
  }

  static $equal_to(boxedVal1, boxedVal2) {
    let value;

    switch (boxedVal1.type) {
      case "boolean": 
        value = boxedVal2.type === "boolean" && boxedVal1.value === boxedVal2.value
        break;
        
      case "float":
      case "integer":
        value = Kernel._areBoxedNumbersEqual(boxedVal1, boxedVal2)
        break;

      default:
        const message = `Kernel.$equal_to(): boxedVal1 = ${JSON.stringify(boxedVal1)}`
        throw new HologramNotImplementedError(message)
    }

    return Utils.freeze({type: "boolean", value: value})
  }

  static if(condition, doClause, elseClause) {
    let result;

    if (Type.isTruthy(condition())) {
      result = doClause()
    } else {
      result = elseClause()
    }

    return Utils.freeze(result)
  }

  static to_string(boxedValue) {
    const value = `${boxedValue.value.toString()}`
    return Utils.freeze({type: 'string', value: value})
  }
}
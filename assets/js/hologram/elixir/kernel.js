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

  static _areBoxedNumbersEqual(boxedNumber1, boxedNumber2) {
    if (Type.isNumber(boxedNumber1) && Type.isNumber(boxedNumber2)) {
      return boxedNumber1.value == boxedNumber2.value
    } else {
      return false
    }
  }

  static $dot(boxedMap, boxedKey) {
    const result = boxedMap.data[Utils.serialize(boxedKey)]
    return Utils.clone(result)
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









  static apply() {
    if (arguments.length == 3) {
      const module = Runtime.getModule(arguments[0].class_name)
      const function_name = arguments[1].value
      const args = arguments[2].data

      return module[function_name](...args)

    } else {
      throw "Kernel.apply: Unsupported yet case!"
    }
  }

  static if(condition, doClause, elseClause) {
    const conditionResult = condition()

    if (Type.isTruthy(conditionResult)) {
      return doClause()
    } else {
      return elseClause()
    }
  }

  static to_string(arg) {
    return {type: 'string', value: `${arg.value.toString()}`}
  }
}
import Runtime from "../runtime"
import Utils from "../utils"

export default class Kernel {
  static $add(arg1, arg2) {
    const type = arg1.type == "integer" && arg2.type == "integer" ? "integer" : "float"
    return {type: type, value: arg1.value + arg2.value}
  }

  static $dot(left, right) {
    return Utils.clone(left.data[Utils.serialize(right)])
  }

  // TODO: implement other types
  static $equal_to(left, right) {
    switch (left.type) {
      case "boolean": 
        const value = right.type == "boolean" && left.value == right.value
        return {type: "boolean", value: value}

      case "float":
        return Kernel._equal_to_number(left, right)

      case "integer":
        return Kernel._equal_to_number(left, right)
    }
  }

  static _equal_to_number(left, right) {
    if (right.type == "integer" || right.type == "float") {
      return {type: "boolean", value: left.value == right.value}

    } else {
      return {type: "boolean", value: false}
    }
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

    if (Utils.isTruthy(conditionResult)) {
      return doClause()
    } else {
      return elseClause()
    }
  }

  static to_string(arg) {
    return {type: 'string', value: `${arg.value.toString()}`}
  }
}
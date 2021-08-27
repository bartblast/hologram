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
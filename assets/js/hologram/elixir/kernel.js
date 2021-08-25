import Utils from "../utils"

export default class Kernel {
  static $add(arg1, arg2) {
    const type = arg1.type == "integer" && arg2.type == "integer" ? "integer" : "float"
    return {type: type, value: arg1.value + arg2.value}
  }

  static $dot(left, right) {
    return Utils.clone(left.data[Utils.serialize(right)])
  }

  static to_string(arg) {
    return {type: 'string', value: `${arg.value.toString()}`}
  }
}
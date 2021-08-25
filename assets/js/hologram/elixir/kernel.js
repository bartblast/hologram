import Utils from "../utils"

export default class Kernel {
  static $add(val1, val2) {
    const type = val1.type == "integer" && val2.type == "integer" ? "integer" : "float"
    return {type: type, value: val1.value + val2.value}
  }

  static $dot(left, right) {
    return Utils.clone(left.data[Utils.serialize(right)])
  }

  static to_string(arg) {
    return {type: 'string', value: `${arg.value.toString()}`}
  }
}
import Utils from "./utils"

export default class Type {
  static atom(value) {
    return Utils.freeze({type: "atom", value: value})
  }

  static boolean(value) {
    return Utils.freeze({type: "boolean", value: value})
  }

  static integer(value) {
    return Utils.freeze({type: "integer", value: value})
  }

  static list(elems) {
    return Utils.freeze({type: "list", data: elems})
  }

  static module(className) {
    return Utils.freeze({type: "module", class_name: className})
  }
}
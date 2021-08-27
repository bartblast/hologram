export default class Type {
  static atom(value) {
    return {type: "atom", value: value}
  }

  static boolean(value) {
    return {type: "boolean", value: value}
  }

  static integer(value) {
    return {type: "integer", value: value}
  }

  static module(className) {
    return {type: "module", class_name: className}
  }
}
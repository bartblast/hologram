export default class Type {
  static boolean(value) {
    return {type: "boolean", value: value}
  }

  static module(className) {
    return {type: "module", class_name: className}
  }
}
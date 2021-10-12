export default class Enums {
  static get OPERATION_METHOD() {
    return {
      action: 0,
      command: 1
    }
  }

  static get OPERATION_SPEC_TYPE() {
    return {
      text: 0,
      expression: 1
    }
  }
}
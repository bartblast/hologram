"use strict";

import Enums from "./enums"
import Utils from "./utils";

export default class Operation {
  static buildMethod(operationSpec) {
    if (operationSpec.modifiers.includes("command")) {
      return Enums.OPERATION_METHOD.command
    } else {
      return Enums.OPERATION_METHOD.action
    }
  }















  construct(method, source, target, name, params) {
    this.method = method
    this.source = source
    this.target = target
    this.name = name
    this.params = params
  }

  static build(operationSpec, eventData) {
    const method = Operation.buildMethod()
    const source = Operation.buildSource()
    const target = Operation.buildTarget()
    const name = Operation.buildName()
    const params = Operation.buildParams(eventData)
    
    const operation = new Operation(method, source, target, name, params)
    return Utils.freeze(operation)
  }
}
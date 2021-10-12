"use strict";

import Enums from "./enums"
import Target from "./target"
import Utils from "./utils";

export default class Operation {
  static buildMethod(operationSpec) {
    if (operationSpec.modifiers.includes("command")) {
      return Enums.OPERATION_METHOD.command
    } else {
      return Enums.OPERATION_METHOD.action
    }
  }

  static getSpecType(operationSpec) {
    const node = operationSpec.value[0];

    if (node.type === "expression") {
      return Enums.OPERATION_SPEC_TYPE.expression
    } else {
      return Enums.OPERATION_SPEC_TYPE.text
    }
  }














  static buildTarget(operationSpec, source) {

    const targetSpec = operationSpecElems[0].value


    switch (targetSpec) {
      case "layout":
        targetModule = context.layoutModule
        targetId = null
        break;

      case "page":
        targetModule = context.pageModule
        targetId = null
        break;

      default:
        targetModule = componentRegistry[target];
        targetId = target
        break;
    }
  }

  construct(method, target, name, params) {
    this.method = method
    this.target = target
    this.name = name
    this.params = params
  }

  static build(operationSpec, eventData) {
    const method = Operation.buildMethod(operationSpec)
    const target = Operation.buildTarget(operationSpec, source)
    const name = Operation.buildName()
    const params = Operation.buildParams(eventData)
    
    const operation = new Operation(method, source, target, name, params)
    return Utils.freeze(operation)
  }
}
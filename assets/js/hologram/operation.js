"use strict";

import Utils from "./utils";

export default class Operation {
  static get METHOD() {
    return {
      action: 0,
      command: 1
    }
  }

  static get SPEC_TYPE() {
    return {
      text: 0,
      expression: 1
    }
  }

  static buildMethod(operationSpec) {
    if (operationSpec.modifiers.includes("command")) {
      return Operation.METHOD.command
    } else {
      return Operation.METHOD.action
    }
  }

  static getSpecType(operationSpec) {
    const node = operationSpec.value[0];

    if (node.type === "expression") {
      return Operation.SPEC_TYPE.expression
    } else {
      return Operation.SPEC_TYPE.text
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
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
      expression: 1,
      text: 0
    }
  }

  static get TARGET() {
    return {
      layout: "__LAYOUT__",
      page: "__PAGE__"
    }
  }

  static buildMethod(operationSpec) {
    if (operationSpec.modifiers.includes("command")) {
      return Operation.METHOD.command
    } else {
      return Operation.METHOD.action
    }
  }

  static buildTarget(operationSpec, bindings, source) {
    if (Operation.getSpecType(operationSpec) === Operation.SPEC_TYPE.text) {
      return source
    }

    const targetSpecValue = operationSpec
      .value[0]
      .callback(bindings)
      .data[0]
      .value

    switch (targetSpecValue) {
      case "layout":
        return Operation.TARGET.layout

      case "page":
        return Operation.TARGET.page

      default:
        return targetSpecValue;
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
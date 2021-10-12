"use strict";

import Type from "./type";
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

  static buildName(operationSpec, bindings) {
    if (Operation.getSpecType(operationSpec) === Operation.SPEC_TYPE.text) {
      const value = operationSpec.value[0].content
      return Type.atom(value)
    }

    const specElems = operationSpec.value[0].callback(bindings).data

    if (specElems.length === 1 || !Type.isAtom(specElems[1])) {
      return specElems[0]
    } else {
      return specElems[1]
    }
  }

  static buildTarget(operationSpec, source, bindings) {
    const targetSpecValue = Operation.getTargetValue(operationSpec, bindings)

    switch (targetSpecValue) {
      case null:
        return source

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

  static getTargetValue(operationSpec, bindings) {
    if (Operation.getSpecType(operationSpec) === Operation.SPEC_TYPE.text) {
      return null
    }

    const specElems = operationSpec.value[0].callback(bindings).data

    if (specElems.length === 1 || !Type.isAtom(specElems[1])) {
      return null
    }

    return specElems[0].value
  }














  

  construct(method, target, name, params) {
    this.method = method
    this.target = target
    this.name = name
    this.params = params
  }

  static build(operationSpec, source, bindings, eventData) {
    const method = Operation.buildMethod(operationSpec)
    const target = Operation.buildTarget(operationSpec, source)
    const name = Operation.buildName(operationSpec, bindings)
    const params = Operation.buildParams(eventData)
    
    const operation = new Operation(method, source, target, name, params)
    return Utils.freeze(operation)
  }
}
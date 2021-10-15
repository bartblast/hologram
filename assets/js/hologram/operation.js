"use strict";

import Keyword from "./elixir/keyword"
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

  construct(target, name, params, method = null) {
    this.method = method
    this.target = target
    this.name = name
    this.params = params
  }

  static build(operationSpec, source, bindings, eventData) {
    const specElems = Operation.getSpecElems(operationSpec, bindings)

    const method = Operation.buildMethod(operationSpec)
    const target = Operation.buildTarget(specElems, source)
    const name = Operation.buildName(specElems)
    const params = Operation.buildParams(specElems, eventData)
    
    const operation = new Operation(target, name, params, method)
    return Utils.freeze(operation)
  }

  static buildMethod(operationSpec) {
    if (operationSpec.modifiers.includes("command")) {
      return Operation.METHOD.command
    } else {
      return Operation.METHOD.action
    }
  }

  static buildName(specElems) {
    if (specElems.length === 1 || !Type.isAtom(specElems[1])) {
      return specElems[0]
    } else {
      return specElems[1]
    }
  }

  static buildParams(specElems, eventData) {
    let params;

    if (specElems.length === 3) {
      params = specElems[2]

    } else if (specElems.length === 2 && Type.isList(specElems[1])) {
      params = specElems[1]

    } else {
      params = Type.list([])
    }

    return Keyword.put(params, Type.atom("event"), eventData)
  }

  static buildTarget(specElems, source) {
    const targetValue = Operation.getTargetValue(specElems)

    switch (targetValue) {
      case null:
        return source

      case "layout":
        return Operation.TARGET.layout

      case "page":
        return Operation.TARGET.page

      default:
        return targetValue;
    }
  }

  static getSpecElems(operationSpec, bindings) {
    let elems;

    if (Operation.getSpecType(operationSpec) === Operation.SPEC_TYPE.text) {
      const value = operationSpec.value[0].content
      elems = [Type.atom(value)]
    } else { // expression
      elems = operationSpec.value[0].callback(bindings).data
    }

    return Utils.freeze(elems)
  }

  static getSpecType(operationSpec) {
    const node = operationSpec.value[0];

    if (node.type === "expression") {
      return Operation.SPEC_TYPE.expression
    } else {
      return Operation.SPEC_TYPE.text
    }
  }

  static getTargetValue(specElems) {
    if (specElems.length === 1 || !Type.isAtom(specElems[1])) {
      return null
    }

    return specElems[0].value
  }
}
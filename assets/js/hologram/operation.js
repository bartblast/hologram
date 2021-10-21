"use strict";

import Keyword from "./elixir/keyword"
import Target from "./target";
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
      layout: "layout",
      page: "page"
    }
  }

  constructor(sourceId, target, name, params, method = null) {
    this.sourceId = sourceId
    this.target = target
    this.name = name
    this.params = params
    this.method = method
  }

  static build(operationSpec, sourceId, bindings, eventData) {
    const specElems = Operation.getSpecElems(operationSpec, bindings)

    const target = Operation.resolveTarget(specElems, sourceId)
    const name = Operation.buildName(specElems)
    const params = Operation.buildParams(specElems, eventData)
    const method = Operation.buildMethod(operationSpec)
    
    const operation = new Operation(sourceId, target, name, params, method)
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

    params = Keyword.put(params, Type.atom("event"), eventData)
    return Type.keywordToMap(params)
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

  static getTargetSpecValue(specElems) {
    if (specElems.length === 1 || !Type.isAtom(specElems[1])) {
      return null
    }

    return specElems[0].value
  }

  static resolveTarget(specElems, sourceId) {
    const targetSpecValue = Operation.getTargetSpecValue(specElems)

    switch (targetSpecValue) {
      case null:
        return new Target(sourceId)

      case "layout":
        return new Target(Operation.TARGET.layout)

      case "page":
        return new Target(Operation.TARGET.page)

      default:
        return new Target(targetSpecValue);
    }
  }
}
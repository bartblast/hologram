"use strict";

import Type from "./type"

export default class Operation {
  constructor(targetModule, targetId, name, params) {
    this.targetModule = targetModule
    this.targetId = targetId
    this.name = name
    this.params = params
  }
  
  static build(operationSpec, context, runtime) {
    const node = operationSpec.value[0];

    if (node.type === "expression") {
      return Operation.buildFromExpressionNodeSpec(node, context, runtime.componentRegistry)

    } else { // node.type === "text"
      return Operation.buildFromTextNodeSpec(node, context)
    }
  }

  static buildFromExpressionNodeSpec(expressionNode, context, componentRegistry) {
    const operationSpecElems = expressionNode.callback(context.bindings).data.data

    if (Operation.hasTarget(operationSpecElems)) {
      return Operation.buildFromExpressionNodeSpecWithTarget(operationSpecElems, context, componentRegistry)
    } else {
      return Operation.buildFromExpressionNodeSpecWithoutTarget(operationSpecElems, context)
    }
  }

  static buildFromExpressionNodeSpecWithTarget(operationSpecElems, context, componentRegistry) {
    const target = operationSpecElems[0].value
    const name = operationSpecElems[1]
    const params = Type.keywordToMap(operationSpecElems[2])
    let targetModule, targetId;

    switch (target) {
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

    return new this(targetModule, targetId, name, params)
  }

  static buildFromExpressionNodeSpecWithoutTarget(operationSpecElems, context) {
    const name = operationSpecElems[0]
    const params = Type.keywordToMap(operationSpecElems[1])

    return new this(context.targetModule, context.targetId, name, params)
  }

  static buildFromTextNodeSpec(textNode, context) {
    const targetModule = context.targetModule
    const targetId = null
    const name = Type.atom(textNode.content)
    const params = Type.map({})
    
    return new this(targetModule, targetId, name, params)
  }

  static hasTarget(operationSpecElems) {
    return operationSpecElems.length >= 2 && Type.isAtom(operationSpecElems[0]) && Type.isAtom(operationSpecElems[1])
  }
}

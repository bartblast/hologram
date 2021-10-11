"use strict";

import Type from "./type"

export default class Operation {
  constructor(targetModule, targetId, name, params, eventData) {
    this.targetModule = targetModule
    this.targetId = targetId
    this.name = name
    this.params = params
    this.eventData = eventData
  }
  
  static build(operationSpec, eventData, context, componentRegistry) {
    const node = operationSpec.value[0];

    if (node.type === "expression") {
      return this.buildFromExpressionNodeSpec(node, eventData, context, componentRegistry)

    } else { // node.type === "text"
      return this.buildFromTextNodeSpec(node, eventData, context)
    }
  }

  static buildFromExpressionNodeSpec(expressionNode, eventData, context, componentRegistry) {
    const operationSpecElems = expressionNode.callback(context.bindings).data.data

    if (Operation.hasTarget(operationSpecElems)) {
      return this.buildFromExpressionNodeSpecWithTarget(operationSpecElems, eventData, context, componentRegistry)
    } else {
      return this.buildFromExpressionNodeSpecWithoutTarget(operationSpecElems, eventData, context)
    }
  }

  static buildFromExpressionNodeSpecWithTarget(operationSpecElems, eventData, context, componentRegistry) {
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

    return new this(targetModule, targetId, name, params, eventData)
  }

  static buildFromExpressionNodeSpecWithoutTarget(operationSpecElems, eventData, context) {
    const name = operationSpecElems[0]
    const params = Type.keywordToMap(operationSpecElems[1])

    return new this(context.targetModule, context.targetId, name, params, eventData)
  }

  static buildFromTextNodeSpec(textNode, eventData, context) {
    const targetModule = context.targetModule
    const targetId = null
    const name = Type.atom(textNode.content)
    const params = Type.map({})
    
    return new this(targetModule, targetId, name, params, eventData)
  }

  static hasTarget(operationSpecElems) {
    return operationSpecElems.length >= 2 && Type.isAtom(operationSpecElems[0]) && Type.isAtom(operationSpecElems[1])
  }
}

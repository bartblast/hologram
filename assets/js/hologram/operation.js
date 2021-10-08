"use strict";

import Type from "./type"

export default class Operation {
  constructor(targetModule, targetId, name, params) {
    this.targetModule = targetModule
    this.targetId = targetId
    this.name = name
    this.params = params
  }

  static buildFromTextNodeSpec(textNode, context) {
    const targetModule = context.targetModule
    const targetId = null
    const name = Type.atom(textNode.content)
    const params = Type.map({})
    
    return new Operation(targetModule, targetId, name, params)
  }
}

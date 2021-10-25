"use strict";

import Command from "./command"
import Operation from "./operation"
import Store from "./store"
import Target from "./target";
import Type from "./type"
import Utils from "./utils"
import VDOM from "./vdom"

export default class Action {
  // Covered implicitely in E2E tests.
  static execute(operation) {
    const targetState = Store.getComponentState(operation.target.id)

    let actionResult = operation.target.class.action(operation.name, operation.params, targetState)
    actionResult = Utils.freeze(actionResult)

    Action.handleResult(actionResult, operation.target)
  }

  static getCommandNameFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data
 
      if (actionResultElems.length === 4) {
        return actionResultElems[2]

      } else if (actionResultElems.length === 3 && Type.isAtom(actionResultElems[2])) {
        return actionResultElems[2]
                
      } else if (actionResultElems.length === 3 && !Type.isAtom(actionResultElems[2])) {
        return actionResultElems[1]

      } else if (actionResultElems.length === 2) {
        return actionResultElems[1]

      } else {
        return null
      }
    }
  }

  static getParamsFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return Type.list([])

    } else { // tuple
      const actionResultElems = actionResult.data
 
      if (actionResultElems.length === 4) {
        return actionResultElems[3]

      } else if (actionResultElems.length === 3 && Type.isList(actionResultElems[2])) {
        return actionResultElems[2]

      } else {
        return Type.list([])
      }
    }
  }

  static getStateFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return actionResult

    } else { // tuple
      return actionResult.data[0]
    }
  }

  static getTargetIdFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data

      if (actionResultElems.length === 4) {
        return actionResultElems[1]

      } else if (actionResultElems.length === 3 && Type.isAtom(actionResultElems[2])) {
        return actionResultElems[1]

      } else {
        return null
      }
    }
  }

  // Covered implicitely in E2E tests.
  static handleResult(actionResult, actionTarget) {
    const newState = Action.getStateFromActionResult(actionResult)
    const commandName = Action.getCommandNameFromActionResult(actionResult)

    Store.setComponentState(actionTarget.id, newState)
    VDOM.render()

    if (commandName) {
      const commandTarget = Action.resolveCommandTarget(actionResult, actionTarget)
      const commandParams = Action.getParamsFromActionResult(actionResult)

      const operation = new Operation(actionTarget.id, commandTarget, commandName, commandParams)
      Command.execute(operation)
    } 
  }

  static resolveCommandTarget(actionResult, actionTarget) {
    const boxedCommandTargetId = Action.getTargetIdFromActionResult(actionResult)
    let commandTargetId;

    if (!boxedCommandTargetId) {
      commandTargetId = actionTarget.id
    } else {
      commandTargetId = boxedCommandTargetId.value
    }

    return new Target(commandTargetId)
  }
}
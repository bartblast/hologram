"use strict";

import Command from "./command"
import DOM from "./dom"
import Operation from "./operation"
import Runtime from "./runtime"
import Store from "./store"
import Type from "./type"
import Utils from "./utils"

export default class Action {
  // TODO: test
  static execute(operation) {
    const componentClass = Runtime.getComponentClass(operation.target)
    const componentState = Store.getComponentState(operation.target)

    let actionResult = componentClass.action(operation.name, operation.params, componentState)
    actionResult = Utils.freeze(actionResult)

    Action.handleResult(actionResult, operation.target)

    return actionResult
  }

  static getCommandNameFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data
 
      if (actionResultElems.length >= 3 && Type.isAtom(actionResultElems[2])) {
        return actionResultElems[2]

      } else if (actionResultElems.length >= 2) {
        return actionResultElems[1]

      } else {
        return null
      }
    }
  }

  static getParamsFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data
 
      if (actionResultElems.length >= 4) {
        return actionResultElems[3]

      } else if (actionResultElems.length >= 3) {
        return actionResultElems[2]

      } else {
        return null
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

  static getTargetFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data

      if (actionResultElems.length >= 3 && Type.isAtom(actionResultElems[2])) {
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

    Store.setComponentState(actionTarget, newState)
    DOM.render()

    if (commandName) {
      const commandTarget = Action.getTargetFromActionResult(actionResult)
      const commandParams = Action.getParamsFromActionResult(actionResult)
      
      const operation = new Operation(Operation.METHOD.command, commandTarget, commandName, commandParams)
      Command.execute(operation)
    } 
  }
}
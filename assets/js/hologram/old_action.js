"use strict";

import Operation from "./operation";
import Type from "./type";

export default class Action extends Operation {
  constructor(targetModule, targetId, name, params, eventData, state) {
    super(targetModule, targetId, name, params, eventData, state)
  }

  // Tested implicitely in E2E tests.
  execute() {
    return this.targetModule.action(this.name, this.params, this.state)
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

  static getCommandParamsFromActionResult(actionResult) {
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

  static getCommandTargetFromActionResult(actionResult) {
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

  static handleResult(result, runtime) {
    const newState = Action.getStateFromActionResult(result)
    const commandName = Action.getCommandNameFromActionResult(result)

    if (commandName) {
      const commandTarget = Action.getCommandTargetFromActionResult(result)
      const commandParams = Action.getCommandParamsFromActionResult(result)
      runtime.client.pushCommand(targetModule, commandName, commandParams, this.handleCommandResponse)
      return null

    } else {
      return [this.targetId, newState]
    }
  }
}
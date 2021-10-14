"use strict";

import Operation from "./operation";
import Type from "./type";

export default class Action extends Operation {
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
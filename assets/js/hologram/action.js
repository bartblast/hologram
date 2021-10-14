"use strict";

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

    handleResult(actionResult)

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

  static getStateFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return actionResult

    } else { // tuple
      return actionResult.data[0]
    }
  }

  // TODO: implement & test
  static handleResult(actionResult) {}
}
"use strict";

import Operation from "./operation";
import Type from "./type";

export default class Action extends Operation {
  constructor(targetModule, targetId, name, params, eventData) {
    super(targetModule, targetId, name, params, eventData)
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
}
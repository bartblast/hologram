"use strict";

import Runtime from "./runtime"
import Store from "./store"

export default class Action {
  // TODO: test
  static execute(operation) {
    const componentClass = Runtime.getComponentClass(operation.target)
    const componentState = Store.getComponentState(operation.target)

    const actionResult = componentClass.action(operation.name, operation.params, componentState)
    handleResult(actionResult)
  }

  // TODO: implement & test
  static handleResult(actionResult) {}
}
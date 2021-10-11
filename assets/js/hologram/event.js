"use strict";

import Action from "./action"
import Command from "./command"
import Runtime from "./runtime";

export default class Event {
  // Tested implicitely in E2E tests.
  static handle(event, operationSpec, context, runtime) {
    event.preventDefault()

    const eventData = this.buildEventData(event)
    const klass = operationSpec.modifiers.includes("command") ? Command : Action
    const operation = klass.build(operationSpec, eventData, context, runtime)

    Runtime.runOperation(operation)
  }
}
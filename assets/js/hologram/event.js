"use strict";

export default class Event {
  // Tested implicitely in E2E tests.
  static handle(event, operationSpec, context, runtime) {
    event.preventDefault()

    const eventData = this.buildEventData(event)
    runtime.executeOperation(operationSpec, eventData, context)
  }
}
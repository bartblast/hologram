"use strict";

import Runtime from "./runtime";

export default class Event {
  // Tested implicitely in E2E tests.
  static handle(event, implementation, source, operationSpec) {
    event.preventDefault()

    const eventData = implementation.buildEventData(event)
    Runtime.executeOperation(operationSpec, source, eventData)
  }
}
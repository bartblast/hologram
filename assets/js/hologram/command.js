"use strict";

import Operation from "./operation";

export default class Command extends Operation {
  constructor(targetModule, targetId, name, params, eventData, state) {
    super(targetModule, targetId, name, params, eventData, state)
  }
}
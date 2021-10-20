"use strict";

import Action from "./action";
import Client from "./client";
import Operation from "./operation";
import Runtime from "./runtime";
import Utils from "./utils";

export default class Command {
  static buildMessagePayload(operation) {
    return {
      target_module: operation.target.module,
      source_id: operation.sourceId,
      command: operation.name,
      params: operation.params,
    }
  }

  // Covered implicitely in E2E tests.
  static execute(operation) {
    const payload = Command.buildMessagePayload(operation)
    Client.pushMessage("command", payload, Command.handleResult)
  }

  // Covered implicitely in E2E tests.
  static handleResult(commandResult) {
    const {data: [target, actionName, params]} = Utils.eval(commandResult)

    if (actionName.value === "__redirect__") {
      Runtime.redirect(params)

    } else {
      const operation = new Operation(target, actionName, params)
      Action.execute(operation)
    }
  }
}
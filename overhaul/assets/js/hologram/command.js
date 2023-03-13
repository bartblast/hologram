"use strict";

import Action from "./action";
import Client from "./client";
import Operation from "./operation";
import Runtime from "./runtime";
import Target from "./target";
import Type from "./type";
import Utils from "./utils";

export default class Command {
  static buildMessagePayload(operation) {
    return {
      target_module: operation.target.module,
      target_id: Type.atom(operation.target.id),
      command: operation.name,
      params: operation.params,
    }
  }

  // Covered implicitely in E2E tests.
  static execute(operation) {
    const payload = Command.buildMessagePayload(operation)
    const callback = (commandResult) => Command.handleResult(commandResult, operation.target.id)
    Client.pushMessage("command", payload, callback)
  }

  // Covered implicitely in E2E tests.
  static handleResult(commandResult, sourceId) {
    const {data: [targetId, actionName, params]} = Utils.eval(commandResult)

    if (actionName.value === "__redirect__") {
      Runtime.redirect(params)

    } else {
      const target = new Target(targetId.value)
      const operation = new Operation(sourceId, target, actionName, params)
      Action.execute(operation)
    }
  }
}
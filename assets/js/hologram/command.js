"use strict";

import Action from "./action";
import Client from "./client";
import Operation from "./operation";
import Runtime from "./runtime";
import Type from "./type";
import Utils from "./utils";

export default class Command {
  // Covered implicitely in E2E tests.
  static execute(operation) {
    const targetClass = Runtime.getComponentClass(operation.target)
    const targetModule = Type.module(targetClass.name)

    const payload = {
      target_module: targetModule,
      name: operation.name,
      params: operation.params,
    }

    Client.pushMessage("command", payload, Command.handleResult)
  }

  // Covered implicitely in E2E tests.
  static handleResult(commandResult) {
    let actionName, params, target;
    [target, actionName, params] = Utils.eval(commandResult)

    if (actionName.value === "__redirect__") {
      Runtime.redirect(params)

    } else {
      const operation = new Operation(Operation.METHOD.action, target, actionName, params)
      Action.execute(operation)
    }
  }
}
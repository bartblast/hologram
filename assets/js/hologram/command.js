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
      target: targetModule,
      command: operation.name,
      params: operation.params,
    }

    Client.pushMessage("command", payload, Command.handleResult)
  }

  // Covered implicitely in E2E tests.
  static handleResult(commandResult) {
    console.debug(commandResult)
    const {data: [actionName, params, target]} = Utils.eval(commandResult)

    if (actionName.value === "__redirect__") {
      Runtime.redirect(params)

    } else {
      const operation = new Operation(target, actionName, params)
      Action.execute(operation)
    }
  }
}
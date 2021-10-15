"use strict";

import Client from "./client";
import Runtime from "./runtime";
import Type from "./type";

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
}
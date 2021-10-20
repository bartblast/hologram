"use strict";

import Operation from "./operation"
import Type from "./type"
import Utils from "./utils"

export default class Store {
  static componentStateRegistry = {}

  static hydrate(serializedState) {
    let state = Utils.eval(serializedState, false)
    state.data[Type.atomKey("context")].data[Type.atomKey("__state__")] = Type.string(serializedState)
    Utils.freeze(state)

    Store.setComponentState(Operation.TARGET.page, state)
    Store.setComponentState(Operation.TARGET.layout, state)
  }

  static getComponentState(componentId) {
    return Store.componentStateRegistry[componentId]
  }

  static setComponentState(componentId, state) {
    Store.componentStateRegistry[componentId] = state
  }
}
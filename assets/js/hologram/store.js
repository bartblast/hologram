"use strict";

import Operation from "./operation"
import Runtime from "./runtime"
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
    const state = Store.componentStateRegistry[componentId]
    return state ? state : null
  }

  static getPageState() {
    return Store.getComponentState(Operation.TARGET.page)
  }

  static resolveComponentState(componentId) {
    if (componentId) {
      let state = Store.getComponentState(componentId)

      if (!state) {
        state = Runtime.getComponentClass(componentId).init()
        Store.setComponentState(componentId, state)
      }

      return state

    } else {
      return Type.map({})
    }
  }

  static setComponentState(componentId, state) {
    Store.componentStateRegistry[componentId] = state
  }
}
"use strict";

export default class Store {
  static componentStateRegistry = {}

  static getComponentState(componentId) {
    return Store.componentStateRegistry[componentId]
  }
}
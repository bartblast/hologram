"use strict";

export default class Store {
  static getInstance(window) {
    if (!window.__hologramStore__) {
      window.__hologramStore__ = new Store()
    }

    return window.__hologramStore__
  }
}
"use strict";

export default class GlobalRegistry {
  static rootKey = "hologram";

  static get(key) {
    return globalThis?.[GlobalRegistry.rootKey]?.[key] || null;
  }

  static set(key, value) {
    if (!globalThis[GlobalRegistry.rootKey]) {
      globalThis[GlobalRegistry.rootKey] = {};
    }

    globalThis[GlobalRegistry.rootKey][key] = value;
  }
}

"use strict";

export default class GlobalRegistry {
  // Made public to make tests easier
  static rootKey = "hologram";

  static append(key, item) {
    const items = $.get(key) || [];
    $.set(key, [...items, item]);
  }

  static get(key) {
    return globalThis?.[$.rootKey]?.[key] || null;
  }

  static set(key, value) {
    if (!globalThis[$.rootKey]) {
      globalThis[$.rootKey] = {};
    }

    globalThis[$.rootKey][key] = value;
  }
}

const $ = GlobalRegistry;

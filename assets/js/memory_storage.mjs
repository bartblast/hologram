"use strict";

export default class MemoryStorage {
  // Made public to make tests easier
  static data = {};

  static get(key) {
    return typeof MemoryStorage.data[key] !== "undefined"
      ? MemoryStorage.data[key]
      : null;
  }

  static put(key, value) {
    MemoryStorage.data[key] = value;
  }
}

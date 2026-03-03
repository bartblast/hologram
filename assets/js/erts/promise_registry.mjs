"use strict";

import Type from "../type.mjs";

export default class PromiseRegistry {
  // Public for easier testing
  static promises = new Map();

  static clear() {
    $.promises = new Map();
  }

  static delete(ref) {
    const key = Type.encodeMapKey(ref);
    $.promises.delete(key);
  }

  static get(ref) {
    const key = Type.encodeMapKey(ref);
    return $.promises.get(key) || null;
  }

  static put(ref, promise) {
    const key = Type.encodeMapKey(ref);
    $.promises.set(key, promise);
  }
}

const $ = PromiseRegistry;

"use strict";

import Type from "../type.mjs";

export default class NativeObjectRegistry {
  // Public for easier testing
  static objects = new Map();

  static clear() {
    $.objects = new Map();
  }

  static get(ref) {
    const key = Type.encodeMapKey(ref);
    return $.objects.has(key) ? $.objects.get(key) : null;
  }

  static put(ref, object) {
    const key = Type.encodeMapKey(ref);
    $.objects.set(key, object);
  }
}

const $ = NativeObjectRegistry;

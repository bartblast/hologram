"use strict";

import Type from "../type.mjs";

export default class BinaryPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  static clear() {
    $.patterns = new Map();
  }

  static get(ref) {
    const key = Type.encodeMapKey(ref);
    return $.patterns.get(key) || null;
  }

  static put(ref, pattern) {
    const key = Type.encodeMapKey(ref);
    $.patterns.set(key, pattern);
  }
}

const $ = BinaryPatternRegistry;

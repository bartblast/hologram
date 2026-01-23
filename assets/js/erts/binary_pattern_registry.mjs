"use strict";

import Bitstring from "../bitstring.mjs";
import Type from "../type.mjs";

export default class BinaryPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  static clear() {
    $.patterns = new Map();
  }

  static get(pattern) {
    const key = Type.encodeMapKey(pattern);
    return $.patterns.get(key) || null;
  }

  static put(pattern, data) {
    const key = Type.encodeMapKey(pattern);
    $.patterns.set(key, data);
  }
}

const $ = BinaryPatternRegistry;

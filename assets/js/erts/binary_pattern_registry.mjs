"use strict";

import Type from "../type.mjs";

export default class BinaryPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  static clear() {
    $.patterns = new Map();
  }

  static get(pattern) {
    return $.patterns.get(pattern) || null;
  }

  static put(pattern, ref) {
    $.patterns.set(pattern, ref);
  }
}

const $ = BinaryPatternRegistry;

"use strict";

export default class BinaryPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  static clear() {
    $.patterns = new Map();
  }

  static get(pattern) {
    return $.patterns.get(pattern) || null;
  }

  static put(pattern, data) {
    $.patterns.set(pattern, data);
  }
}

const $ = BinaryPatternRegistry;

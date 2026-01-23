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
    const key = $.normalizeKey(pattern);
    return $.patterns.get(key) || null;
  }

  static put(pattern, data) {
    const key = $.normalizeKey(pattern);
    $.patterns.set(key, data);
  }

  static normalizeKey(pattern) {
    if (Type.isBinary(pattern)) {
      Bitstring.maybeSetTextFromBytes(pattern);
      return pattern.text;
    } else if (Type.isList(pattern)) {
      const keys = pattern.data.map((item) => {
        Bitstring.maybeSetTextFromBytes(item);
        return item.text;
      });
      return JSON.stringify(keys);
    } else {
      return pattern;
    }
  }
}

const $ = BinaryPatternRegistry;

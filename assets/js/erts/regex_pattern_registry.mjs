"use strict";

import Type from "../type.mjs";

export default class RegexPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  static clear() {
    $.patterns = new Map();
  }

  static get(ref) {
    const key = Type.encodeMapKey(ref);
    return $.patterns.get(key) || null;
  }

  // Returns the registered entry of a compiled {:re_pattern, _, _, _, ref}
  // tuple, or null when the term has another shape or the ref is unknown.
  static lookupByTerm(term) {
    if (!Type.isRecordTuple(term, "re_pattern", 5)) return null;

    return $.get(term.data[4]);
  }

  static put(ref, pattern) {
    const key = Type.encodeMapKey(ref);
    $.patterns.set(key, pattern);
  }
}

const $ = RegexPatternRegistry;

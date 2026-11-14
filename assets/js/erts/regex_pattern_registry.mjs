"use strict";

import Type from "../type.mjs";

export default class RegexPatternRegistry {
  // Public for easier testing
  static patterns = new Map();

  // What :re.import/1 compiled, by import key, so importing the same pattern
  // again reuses it. Public for easier testing. Grows with every distinct
  // source and options pair, see #1211.
  static imports = new Map();

  static clear() {
    $.imports = new Map();
    $.patterns = new Map();
  }

  static get(ref) {
    const key = Type.encodeMapKey(ref);
    return $.patterns.get(key) || null;
  }

  // Returns what was stored under the import key, or null.
  static getImport(key) {
    return $.imports.get(key) || null;
  }

  // Returns the import key of a pattern source and its compile options.
  static importKey(source, options) {
    return Type.encodeMapKey(Type.tuple([source, options]));
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

  static putImport(key, imported) {
    $.imports.set(key, imported);
  }
}

const $ = RegexPatternRegistry;

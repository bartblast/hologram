"use strict";

import Type from "./type.mjs";

// The elements the last finished render put on the page under each ref, by the ref's encoded map
// key, and the page they belong to. They are replaced once a render's patch has given every
// rendered element its live node, so a render that raised leaves the last finished render's
// elements in place. A navigation clears them before anything of the destination exists, so a
// lookup in between finds nothing rather than an element of the page being left.
export default class ElementRefRegistry {
  // Made public to make tests easier
  static elements = new Map();

  // Made public to make tests easier
  static pageModule = null;

  static clear() {
    $.elements = new Map();
    $.pageModule = null;
  }

  // The element rendered under the given ref, or null when nothing is.
  static get(ref) {
    return $.elements.get(Type.encodeMapKey(ref)) ?? null;
  }

  static replace(elementsByRef, pageModule) {
    $.elements = elementsByRef;
    $.pageModule = pageModule;
  }
}

const $ = ElementRefRegistry;

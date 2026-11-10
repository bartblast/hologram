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

  // Made public to make tests easier
  // The literal refs each page renders, as [name, key count] pairs, by the page module's name. Each
  // page's bundle puts its own when it is defined, so the registry holds the names of every page
  // the tab has loaded.
  static pageRefNames = new Map();

  static clear() {
    $.elements = new Map();
    $.pageModule = null;
  }

  // The element rendered under the given ref, or null when nothing is.
  static get(ref) {
    return $.elements.get(Type.encodeMapKey(ref)) ?? null;
  }

  // Puts the literal refs the given page renders, as [name, key count] pairs, by the page module's
  // name.
  static putPageRefNames(pageModuleName, names) {
    $.pageRefNames.set(pageModuleName, names);
  }

  // The literal refs the current page renders, as [name, key count] pairs, or none when no page is
  // shown or its bundle carries none.
  static refNames() {
    return $.pageModule === null
      ? []
      : ($.pageRefNames.get($.pageModule.value) ?? []);
  }

  static replace(elementsByRef, pageModule) {
    $.elements = elementsByRef;
    $.pageModule = pageModule;
  }
}

const $ = ElementRefRegistry;

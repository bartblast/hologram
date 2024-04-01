"use strict";

import Type from "./type.mjs";

export default class ComponentRegistry {
  static data = Type.map([]);

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // deps: [:maps.get/3]
  static getComponentStruct(cid) {
    const entry = ComponentRegistry.getEntry(cid);

    return entry
      ? Erlang_Maps["get/3"](Type.atom("struct"), entry, null)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // deps: [:maps.get/3]
  static getEntry(cid) {
    return Erlang_Maps["get/3"](cid, ComponentRegistry.data, null);
  }

  static hydrate(data) {
    ComponentRegistry.data = data;
  }
}

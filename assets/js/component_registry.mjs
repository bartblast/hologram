"use strict";

import Type from "./type.mjs";

export default class ComponentRegistry {
  static entries = Type.map();

  static clear() {
    ComponentRegistry.entries = Type.map();
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // Deps: [:maps.get/2]
  static getComponentEmittedContext(cid) {
    const componentStruct = ComponentRegistry.getComponentStruct(cid);

    return componentStruct
      ? Erlang_Maps["get/2"](Type.atom("emitted_context"), componentStruct)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // Deps: [:maps.get/3]
  static getComponentModule(cid) {
    const entry = ComponentRegistry.getEntry(cid);

    return entry
      ? Erlang_Maps["get/3"](Type.atom("module"), entry, null)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // Deps: [:maps.get/2]
  static getComponentState(cid) {
    const componentStruct = ComponentRegistry.getComponentStruct(cid);

    return componentStruct
      ? Erlang_Maps["get/2"](Type.atom("state"), componentStruct)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // Deps: [:maps.get/3]
  static getComponentStruct(cid) {
    const entry = ComponentRegistry.getEntry(cid);

    return entry
      ? Erlang_Maps["get/3"](Type.atom("struct"), entry, null)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  // Deps: [:maps.get/3]
  static getEntry(cid) {
    return Erlang_Maps["get/3"](cid, ComponentRegistry.entries, null);
  }

  // Deps: [:maps.is_key/2]
  static isCidRegistered(cid) {
    return Type.isTrue(Erlang_Maps["is_key/2"](cid, ComponentRegistry.entries));
  }

  static populate(entries) {
    ComponentRegistry.entries = entries;
  }

  // Optimized (mutates entries/struct field)
  static putComponentStruct(cid, componentStruct) {
    ComponentRegistry.entries.data[Type.encodeMapKey(cid)][1].data[
      "atom(struct)"
    ][1] = componentStruct;
  }

  // Optimized (mutates entries field)
  static putEntry(cid, entry) {
    ComponentRegistry.entries.data[Type.encodeMapKey(cid)] = [cid, entry];
  }
}

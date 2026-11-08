"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class ComponentRegistry {
  static entries = Type.map();

  static clear() {
    ComponentRegistry.entries = Type.map();
  }

  // Optimized (mutates next_action field in-place)
  static clearNextAction(cid) {
    const entry = ComponentRegistry.entries.data[Type.encodeMapKey(cid)][1];
    const componentStruct = entry.data["atom(struct)"][1];
    componentStruct.data["atom(next_action)"][1] = Type.nil();
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

  // Optimized (mutates props field in-place)
  static putComponentProps(cid, props) {
    const entry = ComponentRegistry.entries.data[Type.encodeMapKey(cid)][1];
    const componentStruct = entry.data["atom(struct)"][1];
    componentStruct.data["atom(props)"][1] = props;
  }

  // Optimized (mutates entries/struct field in-place)
  static putComponentStruct(cid, componentStruct) {
    ComponentRegistry.entries.data[Type.encodeMapKey(cid)][1].data[
      "atom(struct)"
    ][1] = componentStruct;
  }

  // Optimized (mutates entries field in-place)
  static putEntry(cid, entry) {
    ComponentRegistry.entries.data[Type.encodeMapKey(cid)] = [cid, entry];
  }

  // The entries as a page snapshot written to device storage holds them. A secret state entry
  // never reaches storage: it holds its declared default instead, which is also the value a page
  // restored from storage gets back. Props are left empty, since nothing reads them before the
  // mount's first render writes them again, the same reason the server sends them hollow
  // (hollow_props/1). That keeps a secret out of storage when the component passed it down as a
  // child's prop. The registry itself is left as it is, and every state map that changes is a new
  // one, since instances of a module share their defaults map.
  // Deps: [:maps.get/2, :maps.merge/2, :maps.put/3]
  static storableEntries() {
    return Type.map(
      Object.values(ComponentRegistry.entries.data).map(([cid, entry]) => {
        const module = Erlang_Maps["get/2"](Type.atom("module"), entry);
        const struct = Erlang_Maps["get/2"](Type.atom("struct"), entry);

        let storableStruct = Erlang_Maps["put/3"](
          Type.atom("props"),
          Type.map(),
          struct,
        );

        const secretDefaults = ComponentRegistry.#getSecretStateDefaults(
          Interpreter.moduleProxy(module),
        );

        if (secretDefaults.length > 0) {
          const state = Erlang_Maps["get/2"](Type.atom("state"), struct);

          storableStruct = Erlang_Maps["put/3"](
            Type.atom("state"),
            Erlang_Maps["merge/2"](state, Type.map(secretDefaults)),
            storableStruct,
          );
        }

        return [
          cid,
          Erlang_Maps["put/3"](Type.atom("struct"), storableStruct, entry),
        ];
      }),
    );
  }

  // The [key, default] pairs of the module's secret state entries. Every secret entry has a
  // default, which the state macro checks. Cached on the module proxy, since it is a property of
  // the module.
  // Deps: [:lists.keyfind/3]
  static #getSecretStateDefaults(moduleProxy) {
    if (!("__secretStateDefaults__" in moduleProxy)) {
      moduleProxy.__secretStateDefaults__ = moduleProxy["__state__/0"]()
        .data.filter((definition) => {
          const secretEntry = Erlang_Lists["keyfind/3"](
            Type.atom("secret"),
            Type.integer(1),
            definition.data[2],
          );

          return !Type.isFalse(secretEntry) && Type.isTrue(secretEntry.data[1]);
        })
        .map((definition) => [
          definition.data[0],
          Erlang_Lists["keyfind/3"](
            Type.atom("default"),
            Type.integer(1),
            definition.data[2],
          ).data[1],
        ]);
    }

    return moduleProxy.__secretStateDefaults__;
  }
}

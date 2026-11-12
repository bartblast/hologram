"use strict";

import Type from "./type.mjs";

export default class ComponentRegistry {
  static entries = Type.map();

  // The cids whose derived fields were computed after both the last render began and their
  // struct last changed, keyed by encoded cid. A render computes them again for every component it
  // reaches, but the registry keeps a component that left the page, and a render that no longer
  // reaches it leaves its derived fields older than its state after an action, or than the rows
  // they read.
  static currentDerivedCids = new Set();

  static clear() {
    ComponentRegistry.entries = Type.map();
    ComponentRegistry.currentDerivedCids = new Set();
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

  static isDerivedCurrent(cid) {
    return ComponentRegistry.currentDerivedCids.has(Type.encodeMapKey(cid));
  }

  // The entries come from the server or a page snapshot, so no render since they were loaded
  // computed their derived fields.
  static populate(entries) {
    ComponentRegistry.entries = entries;
    ComponentRegistry.currentDerivedCids = new Set();
  }

  // Optimized (mutates derived field in-place)
  static putComponentDerived(cid, derived) {
    const key = Type.encodeMapKey(cid);
    const entry = ComponentRegistry.entries.data[key][1];
    const componentStruct = entry.data["atom(struct)"][1];
    componentStruct.data["atom(derived)"][1] = derived;

    ComponentRegistry.currentDerivedCids.add(key);
  }

  // Optimized (mutates props field in-place)
  static putComponentProps(cid, props) {
    const entry = ComponentRegistry.entries.data[Type.encodeMapKey(cid)][1];
    const componentStruct = entry.data["atom(struct)"][1];
    componentStruct.data["atom(props)"][1] = props;
  }

  // Optimized (mutates entries/struct field in-place)
  //
  // The struct's derived fields were computed from the state it had before, so they are no
  // longer current (see isDerivedCurrent).
  static putComponentStruct(cid, componentStruct) {
    const key = Type.encodeMapKey(cid);
    ComponentRegistry.entries.data[key][1].data["atom(struct)"][1] =
      componentStruct;

    ComponentRegistry.currentDerivedCids.delete(key);
  }

  // A render computes every derived field it reaches again, from the rows as they stand when it
  // begins.
  static resetCurrentDerived() {
    ComponentRegistry.currentDerivedCids = new Set();
  }

  // Optimized (mutates entries field in-place)
  static putEntry(cid, entry) {
    ComponentRegistry.entries.data[Type.encodeMapKey(cid)] = [cid, entry];
  }
}

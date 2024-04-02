"use strict";

import Type from "./type.mjs";

export default class OldComponentRegistry {
  static data = Type.map([]);

  // deps: [Hologram.Component.__struct__/0, :maps.put/3]
  static putComponentEmittedContext(cid, emittedContext) {
    let componentStruct = ComponentRegistry.getComponentStruct(cid);

    if (componentStruct === null) {
      componentStruct = Elixir_Hologram_Component["__struct__/0"]();
    }

    const newComponentStruct = Erlang_Maps["put/3"](
      Type.atom("emitted_context"),
      emittedContext,
      componentStruct,
    );

    ComponentRegistry.putComponentStruct(cid, newComponentStruct);
  }

  // deps: [Hologram.Component.__struct__/0, :maps.put/3]
  static putComponentState(cid, state) {
    let componentStruct = ComponentRegistry.getComponentStruct(cid);

    if (componentStruct === null) {
      componentStruct = Elixir_Hologram_Component["__struct__/0"]();
    }

    const newComponentStruct = Erlang_Maps["put/3"](
      Type.atom("state"),
      state,
      componentStruct,
    );

    ComponentRegistry.putComponentStruct(cid, newComponentStruct);
  }

  // deps: [:maps.put/3]
  static putComponentStruct(cid, data) {
    ComponentRegistry.data = Erlang_Maps["put/3"](
      cid,
      data,
      ComponentRegistry.data,
    );
  }
}

"use strict";

import Type from "./type.mjs";

export default class Store {
  static data = Type.map([]);

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentContext(cid) {
    const componentData = Store.getComponentData(cid);

    return componentData !== null
      ? Erlang_Maps["get/2"](Type.atom("context"), componentData)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentData(cid) {
    return Erlang_Maps["get/3"](cid, Store.data, null);
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentState(cid) {
    const componentData = Store.getComponentData(cid);

    return componentData !== null
      ? Erlang_Maps["get/2"](Type.atom("state"), componentData)
      : null;
  }

  static hydrate(data) {
    Store.data = Erlang_Maps["merge/2"](Store.data, data);
  }

  static putComponentData(cid, data) {
    Store.data = Erlang_Maps["put/3"](cid, data, Store.data);
  }

  // TODO: move to test helpers
  static putComponentContext(cid, context) {
    let componentData = Store.getComponentData(cid);

    if (componentData === null) {
      componentData = Elixir_Hologram_Component_Client["__struct__/0"]();
    }

    const newComponentData = Erlang_Maps["put/3"](
      Type.atom("context"),
      context,
      componentData,
    );

    Store.putComponentData(cid, newComponentData);
  }

  // TODO: move to test helpers
  static putComponentState(cid, state) {
    let componentData = Store.getComponentData(cid);

    if (componentData === null) {
      componentData = Elixir_Hologram_Component_Client["__struct__/0"]();
    }

    const newComponentData = Erlang_Maps["put/3"](
      Type.atom("state"),
      state,
      componentData,
    );

    Store.putComponentData(cid, newComponentData);
  }
}

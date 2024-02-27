"use strict";

import Type from "./type.mjs";

export default class Store {
  static data = Type.map([]);

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentContext(cid) {
    const componentStruct = Store.getComponentStruct(cid);

    return componentStruct !== null
      ? Erlang_Maps["get/2"](Type.atom("context"), componentStruct)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentState(cid) {
    const componentStruct = Store.getComponentStruct(cid);

    return componentStruct !== null
      ? Erlang_Maps["get/2"](Type.atom("state"), componentStruct)
      : null;
  }

  // null instead of boxed nil is returned by default on purpose, because the function is not used by transpiled code.
  static getComponentStruct(cid) {
    return Erlang_Maps["get/3"](cid, Store.data, null);
  }

  static hydrate(data) {
    Store.data = Erlang_Maps["merge/2"](Store.data, data);
  }

  static putComponentContext(cid, context) {
    let componentStruct = Store.getComponentStruct(cid);

    if (componentStruct === null) {
      componentStruct = Elixir_Hologram_Component["__struct__/0"]();
    }

    const newComponentStruct = Erlang_Maps["put/3"](
      Type.atom("context"),
      context,
      componentStruct,
    );

    Store.putComponentStruct(cid, newComponentStruct);
  }

  static putComponentState(cid, state) {
    let componentStruct = Store.getComponentStruct(cid);

    if (componentStruct === null) {
      componentStruct = Elixir_Hologram_Component["__struct__/0"]();
    }

    const newComponentStruct = Erlang_Maps["put/3"](
      Type.atom("state"),
      state,
      componentStruct,
    );

    Store.putComponentStruct(cid, newComponentStruct);
  }

  static putComponentStruct(cid, data) {
    Store.data = Erlang_Maps["put/3"](cid, data, Store.data);
  }
}

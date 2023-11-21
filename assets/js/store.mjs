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
}

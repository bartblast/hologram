"use strict";

import Type from "./type.mjs";

export default class Store {
  static data = Type.map([]);

  static getComponentData(cid) {
    // null instead of boxed nil is returned by default on purpose
    return Erlang_Maps["get/3"](cid, Store.data, null);
  }

  static hydrate(data) {
    Store.data = Erlang_Maps["merge/2"](Store.data, data);
  }
}

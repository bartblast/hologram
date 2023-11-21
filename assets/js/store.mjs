"use strict";

import Type from "./type.mjs";

export default class Store {
  static data = Type.map([]);

  static hydrate(data) {
    Store.data = Erlang_Maps["merge/2"](Store.data, data);
  }
}

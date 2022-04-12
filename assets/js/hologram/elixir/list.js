"use strict";

import Utils from "../utils";
import Type from "../type";

export default class List {
  static insert_at(list, index, value) {

    if (index === -1) {
      index = list.data.length
    } else if (index < 0) {
      index = index + 1
    }

    const elems = Utils.clone(list.data)
    elems.splice(index, 0, value)
    return Type.list(elems)
  }
}
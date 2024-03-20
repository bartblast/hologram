"use strict";

import Type from "../type";
import Utils from "../utils";

export default class Keyword {
  static put(keywords, key, value) {
    const keywordsWithKeyDeleted = Keyword.delete(keywords, key)
    const newElems = Utils.clone(keywordsWithKeyDeleted.data)
    newElems.unshift(Type.tuple([key, value]))

    return Type.list(newElems)
  }
}
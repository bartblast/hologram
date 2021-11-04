"use strict";

import Type from "../type";
import Utils from "../utils";

export default class Keyword {
  static delete(keywords, key) {
    const newElems = keywords.data.filter((elem) => {
      return !Utils.isEqual(elem.data[0], key)
    })

    return Utils.freeze(Type.list(newElems))
  }

  static has_key$question(keywords, key) {
    if (keywords.data.find(el => Utils.isEqual(el.data[0], key))) {
      return Type.boolean(true)
    } else {
      return Type.boolean(false)
    }
  }

  static put(keywords, key, value) {
    const keywordsWithKeyDeleted = Keyword.delete(keywords, key)
    const newElems = Utils.clone(keywordsWithKeyDeleted.data)
    newElems.unshift(Type.tuple([key, value]))

    return Type.list(newElems)
  }
}
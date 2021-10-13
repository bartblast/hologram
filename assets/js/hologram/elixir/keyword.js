"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual";

import Type from "../type";
import Utils from "../utils";

export default class Keyword {
  static delete(keywords, key) {
    const newElems = keywords.data.filter((elem) => {
      return !isEqual(elem.data[0], key)
    })

    return Utils.freeze(Type.list(newElems))
  }

  static has_key$question(keywords, key) {
    if (keywords.data.find(el => isEqual(el.data[0], key))) {
      return Type.boolean(true)
    } else {
      return Type.boolean(false)
    }
  }
}
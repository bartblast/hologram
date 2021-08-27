// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual";

import Type from "../type";

export default class Keyword {
  static has_key$question(keywords, key) {
    if (keywords.data.find(el => isEqual(el.data[0], key))) {
      return Type.boolean(true)
    } else {
      return Type.boolean(false)
    }
  }
}
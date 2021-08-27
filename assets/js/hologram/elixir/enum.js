// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual";

import Type from "../type";

export default class Enum {
  static member$question(enumerable, element) {
    switch (enumerable.type) {
      case "list":
        if (enumerable.data.find(el => isEqual(el, element))) {
          return Type.boolean(true)
        } else {
          return Type.boolean(false)
        }

      // DEFER: implement other enumerable types
      default: 
        throw `Enum.member$question: Type not supported yet: ${enumerable.type}`
    }
  }
}
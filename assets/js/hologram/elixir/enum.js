// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual";

export default class Enum {
  static member$question(enumerable, element) {
    switch (enumerable.type) {
      case "list":
        if (enumerable.data.find(el => isEqual(el, element))) {
          return {type: "boolean", value: true}
        } else {
          return {type: "boolean", value: false}
        }

      // DEFER: implement other enumerable types
      default: 
        throw `Enum.member$question: Type not supported yet: ${enumerable.type}`
    }
  }
}
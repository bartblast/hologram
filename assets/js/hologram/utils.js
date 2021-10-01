"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import HologramNotImplementedError from "./errors";

export default class Utils {
  static clone(obj) {
    const cloned = cloneDeep(obj)
    return Utils.freeze(cloned)
  }

  static eval(code) {
    const result = (new Function(`return (${code});`)());
    return Utils.freeze(result)
  }

  // based on deepFreeze() from: https://developer.mozilla.org/pl/docs/Web/JavaScript/Reference/Global_Objects/Object/freeze
  static freeze(obj) {
    const props = Object.getOwnPropertyNames(obj);
    
    for (const prop of props) {
      const val = obj[prop];
  
      if (val && typeof val === "object") {
        Utils.freeze(val);
      }
    }
  
    return Object.freeze(obj);
  }

  static isFalse(boxedValue) {
    return boxedValue.type === "boolean" && boxedValue.value === false
  }

  static isFalsy(boxedValue) {
    return Utils.isFalse(boxedValue) || Utils.isNil(boxedValue)
  }

  static isNil(boxedValue) {
    return boxedValue.type === "nil"
  }

  static isTruthy(boxedValue) {
    return !Utils.isFalsy(boxedValue)
  }

  static keywordToMap(keyword) {
    const result = keyword.data.reduce((acc, elem) => {
      const key = Utils.serialize(elem.data[0])
      acc.data[key] = elem.data[1]
      return acc
    }, {type: "map", data: {}})

    return Utils.freeze(result)
  }

  static serialize(boxedValue) {
    switch (boxedValue.type) {
      case "atom":
        return `~atom[${boxedValue.value}]`

      case "string":
        return `~string[${boxedValue.value}]`
        
      default:
        const message = `Utils.serialize(): boxedValue = ${JSON.stringify(boxedValue)}`
        throw new HologramNotImplementedError(message)
    }
  }
}
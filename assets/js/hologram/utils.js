"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

export default class Utils {
  static clone(value) {
    return cloneDeep(value)
  }

  static eval(code) {
    return (new Function(`return (${code});`)());
  }

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

  static isFalse(arg) {
    return arg.type == "boolean" && arg.value == false
  }

  static isFalsy(arg) {
    return Utils.isFalse(arg) || Utils.isNil(arg)
  }

  static isNil(arg) {
    return arg.type == "nil"
  }

  static isTruthy(arg) {
    return !Utils.isFalsy(arg)
  }

  static keywordToMap(keyword) {
    return keyword.data.reduce((acc, elem) => {
      const key = Utils.serialize(elem.data[0])
      acc.data[key] = elem.data[1]
      return acc
    }, {type: "map", data: {}})
  }

  static serialize(arg) {
    switch (arg.type) {
      case 'atom':
        return `~atom[${arg.value}]`

      case 'string':
        return `~string[${arg.value}]`
        
      default:
        throw 'Not implemented, at Utils.serialize()'
    }
  }
}

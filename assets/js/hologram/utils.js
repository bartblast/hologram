"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";
import isEqual from "lodash/isEqual";

export default class Utils {
  static clone(obj) {
    return cloneDeep(obj)
  }

  static eval(code, immutable = true) {
    const result = (new Function(`return (${code});`)());
    return immutable ? Utils.freeze(result) : result
  }

  static exec(code) {
    (new Function(`${code};`)());
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

  static isEqual(left, right) {
    return isEqual(left, right)
  }
}
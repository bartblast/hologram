"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

export default class Utils {
  static clone(obj) {
    return cloneDeep(obj)
  }

  static eval(code, freeze = true) {
    const result = (new Function(`return (${code});`)());
    return freeze ? Utils.freeze(result) : result
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
}
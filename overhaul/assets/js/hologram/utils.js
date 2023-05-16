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

  static isEqual(left, right) {
    return isEqual(left, right)
  }
}
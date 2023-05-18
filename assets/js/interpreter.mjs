"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual.js";
import Type from "./type.mjs";

export default class Interpreter {
  static consOperator(left, right) {
    return Type.list([left].concat(right.data));
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }
}

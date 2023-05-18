"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual.js";

import Type from "./type.mjs";

export default class Interpreter {
  static consOperator(left, right) {
    return Type.list([left].concat(right.data));
  }

  static count(enumerable) {
    if (Type.isMap(enumerable)) {
      return Object.keys(enumerable.data).length;
    }

    return enumerable.data.length;
  }

  static head(list) {
    return list.data[0];
  }

  static isStrictlyEqual(left, right) {
    if (left.type !== right.type) {
      return false;
    }

    return isEqual(left, right);
  }

  static tail(list) {
    return Type.list(list.data.slice(1));
  }
}

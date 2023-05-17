"use strict";

import Type from "../type.mjs";

export default class erlang {
  // start: is_float/1
  static is_float(term) {
    return Type.boolean(Type.isFloat(term))
  }
  // end: is_float/1

  // start: is_number/1
  static is_number(term) {
    return Type.isNumber(term)
  }
  // end: is_number/1
}
"use strict";

import Type from "../type.mjs";

export default class erlang {
  // start: is_number/1
  static is_number(term) {
    return Type.isNumber(term)
  }
  // end: is_number/1
}
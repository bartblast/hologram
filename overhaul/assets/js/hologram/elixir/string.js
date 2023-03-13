"use strict";

import Type from "../type";

export default class String {
  static to_atom(boxedString) {
    return Type.atom(boxedString.value)
  }
}
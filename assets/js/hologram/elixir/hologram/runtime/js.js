"use strict";

import Type from "../../../type";
import Utils from "../../../utils";

export default class JS {
  static exec(code) {
    Utils.eval(code)
    return Type.nil()
  }
}
"use strict";

import Kernel from "../../../elixir/kernel"
import Utils from "../../../utils";

export default class JS {
  static exec(boxedCode) {
    Utils.exec(Kernel.to_string(boxedCode).value)
  }
}
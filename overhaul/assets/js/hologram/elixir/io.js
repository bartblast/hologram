"use strict";

import Type from "../type";

export default class IO {
  // DEFER: implement inspect/2 and inspect/3
  static inspect(val) {
    console.debug(val)
    return val
  }

  // DEFER: test and consider the device param
  static puts(str) {
    console.log(str)
    return Type.atom("ok")
  }
}
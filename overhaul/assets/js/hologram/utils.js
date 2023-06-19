"use strict";

export default class Utils {
  static exec(code) {
    (new Function(`${code};`)());
  }
}
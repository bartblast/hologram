"use strict";

export default class Utils {
  static eval(code, immutable = true) {
    const result = (new Function(`return (${code});`)());
    return immutable ? Utils.freeze(result) : result
  }

  static exec(code) {
    (new Function(`${code};`)());
  }
}
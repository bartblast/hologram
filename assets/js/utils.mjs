"use strict";

export default class Utils {
  // Based on deepFreeze() from: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/freeze
  static freeze(obj) {
    const props = Object.getOwnPropertyNames(obj);
    
    for (const prop of props) {
      const val = obj[prop];

      if (val && typeof val === "object") {
        Utils.freeze(val);
      }
    }

    return Object.freeze(obj);
  }
}
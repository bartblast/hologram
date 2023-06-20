"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep.js";
import Hologram from "./hologram.mjs";

export default class Utils {
  // Based on: https://stackoverflow.com/a/43053803
  static cartesianProduct(sets) {
    if (sets.length === 1) {
      return sets[0].map((item) => [item]);
    }

    if (sets.length === 0) {
      return [];
    }

    return sets.reduce((a, b) => a.flatMap((d) => b.map((e) => [d, e].flat())));
  }

  static clone(obj) {
    return cloneDeep(obj);
  }

  static concatUint8Arrays(arrays) {
    return arrays.reduce((acc, arr) => {
      const mergedArr = new Uint8Array(acc.length + arr.length);
      mergedArr.set(acc);
      mergedArr.set(arr, acc.length);

      return mergedArr;
    }, new Uint8Array());
  }

  static debug(term) {
    console.log(Hologram.serialize(term));

    return term;
  }

  static evaluate(code, immutable = true) {
    const result = new Function(`return (${code});`)();
    return immutable ? Utils.freeze(result) : result;
  }

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

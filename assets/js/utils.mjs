"use strict";

// See: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep.js";

export default class Utils {
  static capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

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

  static chunkArray(array, chunkSize) {
    const result = [];

    for (let i = 0; i < array.length; i += chunkSize) {
      const chunk = array.slice(i, i + chunkSize);
      result.push(chunk);
    }

    return result;
  }

  static cloneDeep(context) {
    return cloneDeep(context);
  }

  static concatUint8Arrays(arrays) {
    return arrays.reduce((acc, arr) => {
      const mergedArr = new Uint8Array(acc.length + arr.length);
      mergedArr.set(acc);
      mergedArr.set(arr, acc.length);

      return mergedArr;
    }, new Uint8Array());
  }

  static naiveNounPlural(noun, count) {
    const enPluralRules = new Intl.PluralRules("en-US");

    return `${noun}${enPluralRules.select(count) === "one" ? "" : "s"}`;
  }
}

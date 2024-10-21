"use strict";

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

  static ordinal(number) {
    const enOrdinalRules = new Intl.PluralRules("en-US", {type: "ordinal"});

    switch (enOrdinalRules.select(number)) {
      case "one":
        return `${number}st`;

      case "two":
        return `${number}nd`;

      case "few":
        return `${number}rd`;

      case "other":
        return `${number}th`;
    }
  }

  static async runAsyncTask(task) {
    return new Promise((resolve) => {
      setTimeout(() => {
        task();
        resolve();
      }, 0);
    });
  }

  static shallowCloneArray(arr) {
    return [...arr];
  }

  static shallowCloneObject(obj) {
    // Use {...obj} instead of Object.assign({}, obj) for shallow copying,
    // see benchmarks here: https://thecodebarbarian.com/object-assign-vs-object-spread.html
    return {...obj};
  }
}

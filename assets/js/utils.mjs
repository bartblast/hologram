"use strict";

export default class Utils {
  static capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
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

  static randomUUID() {
    // crypto.randomUUID() is only exposed in secure contexts (HTTPS or
    // localhost). When the app is served over plain HTTP from another hostname
    // (e.g. a LAN IP) it is unavailable, so fall back to generating an RFC 4122
    // version 4 UUID from crypto.getRandomValues(), which is not gated on
    // secure contexts and is still cryptographically strong.
    if (typeof crypto.randomUUID === "function") {
      return crypto.randomUUID();
    }

    const bytes = crypto.getRandomValues(new Uint8Array(16));

    // Set the version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const hex = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  static randomUint32() {
    return (Math.random() * 0x100000000) >>> 0;
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

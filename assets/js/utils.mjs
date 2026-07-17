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

  static uuidv7() {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);

    const unixMs = Date.now();

    bytes[0] = Math.floor(unixMs / 2 ** 40) % 256;
    bytes[1] = Math.floor(unixMs / 2 ** 32) % 256;
    bytes[2] = Math.floor(unixMs / 2 ** 24) % 256;
    bytes[3] = Math.floor(unixMs / 2 ** 16) % 256;
    bytes[4] = Math.floor(unixMs / 2 ** 8) % 256;
    bytes[5] = unixMs % 256;

    // Version 7 in the high nibble, keeping 4 random bits in the low nibble
    bytes[6] = 0x70 | (bytes[6] & 0x0f);

    // Variant 0b10 in the two high bits, keeping 6 random bits
    bytes[8] = 0x80 | (bytes[8] & 0x3f);

    const hex = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
}

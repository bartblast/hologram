"use strict";

export default class Utils {
  // The millisecond and counter of the last UUID uuidv7/0 returned.
  static #uuidv7LastMs = -1;
  static #uuidv7Counter = 0;

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

  static stringify(value) {
    return JSON.stringify(value, (_key, item) =>
      typeof item === "bigint" ? item.toString() : item,
    );
  }

  // For a body the server has to parse. JSON escapes a lone surrogate, half of a pair, and the
  // server's parser refuses the whole body for it, so each one goes out as U+FFFD, which is what
  // its bytes already are. Only values are read: a key here is a name from the model.
  static stringifyWellFormed(value) {
    return JSON.stringify(value, (_key, item) => {
      if (typeof item === "bigint") {
        return item.toString();
      }

      return typeof item === "string" ? item.toWellFormed() : item;
    });
  }

  // Each call's UUID sorts after the one before it, even within a millisecond: the 12 bits after
  // the version hold a counter that starts at a random value below 2048 each new millisecond and
  // counts up within it, and once it runs out the timestamp moves on to the next millisecond
  // (RFC 9562, section 6.2, method 1). The rows a client creates then keep their order by id.
  static uuidv7() {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);

    const now = Date.now();

    if (now > Utils.#uuidv7LastMs) {
      Utils.#uuidv7LastMs = now;
      Utils.#uuidv7Counter = ((bytes[6] & 0x07) << 8) | bytes[7];
    } else if (Utils.#uuidv7Counter < 0xfff) {
      Utils.#uuidv7Counter += 1;
    } else {
      Utils.#uuidv7LastMs += 1;
      Utils.#uuidv7Counter = ((bytes[6] & 0x07) << 8) | bytes[7];
    }

    const unixMs = Utils.#uuidv7LastMs;
    const counter = Utils.#uuidv7Counter;

    bytes[0] = Math.floor(unixMs / 2 ** 40) % 256;
    bytes[1] = Math.floor(unixMs / 2 ** 32) % 256;
    bytes[2] = Math.floor(unixMs / 2 ** 24) % 256;
    bytes[3] = Math.floor(unixMs / 2 ** 16) % 256;
    bytes[4] = Math.floor(unixMs / 2 ** 8) % 256;
    bytes[5] = unixMs % 256;

    // Version 7 in the high nibble, then the counter's 12 bits
    bytes[6] = 0x70 | (counter >> 8);
    bytes[7] = counter & 0xff;

    // Variant 0b10 in the two high bits, keeping 6 random bits
    bytes[8] = 0x80 | (bytes[8] & 0x3f);

    const hex = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
}

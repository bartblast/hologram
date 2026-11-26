"use strict";

export default class Utils {
  // The digits an entity id is written in, in ASCII order, so that ids of one width sort as strings
  // in the order of the numbers they write.
  static #BASE62 =
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

  // 2^128 - 1 in base62, the largest number 22 of its digits may write that 16 bytes hold.
  static #MAX_ENTITY_ID = "7n42DGM5Tflk9n8mt7Fhc7";

  // The millisecond and counter of the last UUIDv7 bytes uuidv7/0 or entityId/0 were built on.
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

  // The twin of Hologram.DB.Codec.decode(<<_::128>>, :id): the 16 bytes as the big-endian number
  // they hold, in 22 base62 digits, zero padded.
  static entityIdFromBytes(bytes) {
    let number = 0n;

    for (const byte of bytes) {
      number = (number << 8n) | BigInt(byte);
    }

    let id = "";

    for (let index = 0; index < 22; index++) {
      id = Utils.#BASE62[Number(number % 62n)] + id;
      number /= 62n;
    }

    return id;
  }

  // An entity id the way the server spelled it before ids were short, the lowercase 8-4-4-4-12
  // form of the same number - what a grant id is derived from. The given id is taken to be valid.
  static entityIdToUuid(id) {
    let number = 0n;

    for (const char of id) {
      number = number * 62n + BigInt(Utils.#BASE62.indexOf(char));
    }

    return Utils.#uuidSpelling(number.toString(16).padStart(32, "0"));
  }

  // Each call's id sorts after the one before it, as uuidv7/0's UUIDs do: an entity id is the same
  // UUIDv7 bytes, written in base62 (see entityIdFromBytes/1), whose fixed width and ASCII ordered
  // digits keep the bytes' order. The rows a client creates then keep their order by id.
  static entityId() {
    return Utils.entityIdFromBytes(Utils.#uuidv7Bytes());
  }

  // The twin of the :id check in Hologram.Entity.Validator: 22 base62 digits writing a number 16
  // bytes hold. One spelling per id, since both tiers compare ids as strings.
  static isEntityId(value) {
    return (
      typeof value === "string" &&
      /^[0-9A-Za-z]{22}$/.test(value) &&
      value <= Utils.#MAX_ENTITY_ID
    );
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
  // (RFC 9562, section 6.2, method 1). For the ids that aren't entity ids, which entityId/0 makes.
  static uuidv7() {
    const hex = Array.from(Utils.#uuidv7Bytes(), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    return Utils.#uuidSpelling(hex);
  }

  static #uuidSpelling(hex) {
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  // One generator for uuidv7/0 and entityId/0, so the two share the millisecond and the counter
  // and each call's bytes sort after the last call's, whichever of the two made them.
  static #uuidv7Bytes() {
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

    return bytes;
  }
}

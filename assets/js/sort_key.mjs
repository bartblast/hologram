"use strict";

// Computes practical-order sort keys for string attribute values - the derived values that
// order_by companion columns store and both tiers compare. Hologram.DB.SortKey is the reference
// implementation, pinned by mirrored suites: the version 1 rules are frozen, and a version bump
// regenerates every stored key from source values on both tiers.

export default class SortKey {
  // The pinned strip ranges cover marks that dictionaries ignore: general combining diacritics,
  // Hebrew niqqud, and Arabic harakat. Indic vowel signs stay deliberately unstripped - they
  // distinguish words.
  static #combiningMarkRanges = [
    [0x0300, 0x036f],
    [0x05b0, 0x05bc],
    [0x05c7, 0x05c7],
    [0x064b, 0x065f],
    [0x0670, 0x0670],
    [0x1ab0, 0x1aff],
    [0x1dc0, 0x1dff],
    [0x20d0, 0x20ff],
    [0xfe20, 0xfe2f],
  ];

  // Letters NFD cannot decompose, folded to their dictionary neighbors.
  static #foldMap = {
    ß: "ss",
    æ: "ae",
    đ: "d",
    ħ: "h",
    ı: "i",
    ĸ: "k",
    ł: "l",
    ŋ: "n",
    œ: "oe",
    ð: "d",
    ø: "o",
    þ: "th",
    ſ: "s",
  };

  static #maxKeyBytes = 64;

  // Computes the sort key of the given string value - downcased, canonically decomposed, with
  // ignorable combining marks stripped and non-decomposable letters folded, capped at a
  // byte-size prefix that never splits a codepoint.
  static compute(value) {
    const decomposed = value.toLowerCase().normalize("NFD");
    const stripped = SortKey.#stripCombiningMarks(decomposed);
    const folded = SortKey.#foldLetters(stripped);

    return SortKey.#cap(folded);
  }

  // Returns the version of the sort-key rule set.
  static version() {
    return 1;
  }

  static #cap(text) {
    let byteCount = 0;
    let result = "";

    for (const char of text) {
      byteCount += SortKey.#utf8ByteSize(char.codePointAt(0));

      if (byteCount > SortKey.#maxKeyBytes) {
        break;
      }

      result += char;
    }

    return result;
  }

  static #foldLetters(text) {
    let result = "";

    for (const char of text) {
      result += SortKey.#foldMap[char] ?? char;
    }

    return result;
  }

  static #isCombiningMark(codepoint) {
    return SortKey.#combiningMarkRanges.some(
      ([first, last]) => codepoint >= first && codepoint <= last,
    );
  }

  static #stripCombiningMarks(text) {
    let result = "";

    for (const char of text) {
      if (!SortKey.#isCombiningMark(char.codePointAt(0))) {
        result += char;
      }
    }

    return result;
  }

  static #utf8ByteSize(codepoint) {
    if (codepoint < 0x80) {
      return 1;
    }

    if (codepoint < 0x800) {
      return 2;
    }

    if (codepoint < 0x10000) {
      return 3;
    }

    return 4;
  }
}

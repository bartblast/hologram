"use strict";

// IMPORTANT!
// This module has a twin in lib/hologram/db/sort_key.ex, and their suites mirror each other case
// for case (test/javascript/sort_key_test.mjs and test/elixir/hologram/db/sort_key_test.exs).
// Always update all four together: a rule that holds on one tier and not the other sorts a
// client's own rows differently from the server's, silently, and only for the values the rule
// touches.
//
// Computes practical-order sort keys for string attribute values - the derived values that
// order_by companion columns store and both tiers compare. Hologram.DB.SortKey is the reference
// implementation: the version 1 rules are frozen, and a version bump regenerates every stored key
// from source values on both tiers.
//
// Where the tiers cannot be made to agree: the two runtimes carry Unicode case tables of different
// vintages, so a handful of very recently assigned codepoints (measured at 28 in V8 under Node 23
// against OTP 28 - three in Latin Extended-D, the rest in the 0x16EA0 run) downcase on one tier and
// not the other. Nothing here can close that without shipping our own case tables, and it resolves
// as the runtimes catch up.

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
  //
  // Greek sigma is here for two reasons at once. It is one letter with two lowercase spellings, so
  // folding them together is what puts ΑΘΗΝΑΣ beside αθηνας the way a dictionary does. It is ALSO
  // what makes the tiers agree: toLowerCase applies Unicode's Final_Sigma mapping and Elixir's
  // String.downcase/1 does not, so the same word reaches this fold spelled differently on each
  // side - and leaves it spelled the same.
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
    ς: "σ",
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

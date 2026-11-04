"use strict";

// Compares strings the way Elixir and Postgres do - by code point - rather than the way
// JavaScript's < does, by UTF-16 code unit.
//
// The two orders agree everywhere but one place: a character above U+FFFF is stored as two
// surrogate code units (0xD800-0xDFFF), which sort BELOW the code units 0xE000-0xFFFF, while the
// character itself sorts above them. So "😀" < U+FFFD in JavaScript, and the other way around on
// the server, and a client sorting its own rows would put them where the server doesn't.
export default class StringOrder {
  static #HIGH_UNIT = /[\ud800-\uffff]/;

  // Returns -1, 0 or 1. Only the first code units that differ decide, and only when both are at or
  // above 0xD800 do they need moving: surrogates up past 0xFFFF, the units above them down into the
  // gap the surrogates leave. A string with no such unit can't hold one at that position, so the
  // native comparison already gives the right answer, and most strings never reach the loop.
  static compare(left, right) {
    if (left === right) {
      return 0;
    }

    if (
      !StringOrder.#HIGH_UNIT.test(left) ||
      !StringOrder.#HIGH_UNIT.test(right)
    ) {
      return left < right ? -1 : 1;
    }

    const length = Math.min(left.length, right.length);

    for (let index = 0; index < length; index++) {
      const leftUnit = left.charCodeAt(index);
      const rightUnit = right.charCodeAt(index);

      if (leftUnit !== rightUnit) {
        if (leftUnit >= 0xd800 && rightUnit >= 0xd800) {
          return StringOrder.#codePointRank(leftUnit) <
            StringOrder.#codePointRank(rightUnit)
            ? -1
            : 1;
        }

        return leftUnit < rightUnit ? -1 : 1;
      }
    }

    return left.length < right.length ? -1 : 1;
  }

  static #codePointRank(unit) {
    return unit >= 0xe000 ? unit - 0x800 : unit + 0x2000;
  }
}

"use strict";

// Constants are alphabetical within each group.

// --- Shared ranges (referenced by the exported tables, so declared first) ---

const DIGIT_RANGES = [[0x30, 0x39]];

const SPACE_RANGES = [
  [0x09, 0x0d],
  [0x20, 0x20],
];

const WORD_RANGES = [
  [0x30, 0x39],
  [0x41, 0x5a],
  [0x5f, 0x5f],
  [0x61, 0x7a],
];

// --- Exported tables ---

// PCRE2 character sets of the POSIX classes, as sorted code point ranges.
export const POSIX_SETS = {
  alnum: [
    [0x30, 0x39],
    [0x41, 0x5a],
    [0x61, 0x7a],
  ],
  alpha: [
    [0x41, 0x5a],
    [0x61, 0x7a],
  ],
  ascii: [[0x00, 0x7f]],
  blank: [
    [0x09, 0x09],
    [0x20, 0x20],
  ],
  cntrl: [
    [0x00, 0x1f],
    [0x7f, 0x7f],
  ],
  digit: DIGIT_RANGES,
  graph: [[0x21, 0x7e]],
  lower: [[0x61, 0x7a]],
  print: [[0x20, 0x7e]],
  punct: [
    [0x21, 0x2f],
    [0x3a, 0x40],
    [0x5b, 0x60],
    [0x7b, 0x7e],
  ],
  space: SPACE_RANGES,
  upper: [[0x41, 0x5a]],
  word: WORD_RANGES,
  xdigit: [
    [0x30, 0x39],
    [0x41, 0x46],
    [0x61, 0x66],
  ],
};

// PCRE2 character sets of the shorthand class escapes, as sorted code point
// ranges. The d and w sets match the JS \d and \w escapes exactly, the others
// differ from their JS counterparts.
export const SHORTHAND_SETS = {
  d: DIGIT_RANGES,
  h: [
    [0x09, 0x09],
    [0x20, 0x20],
    [0xa0, 0xa0],
    [0x1680, 0x1680],
    [0x180e, 0x180e],
    [0x2000, 0x200a],
    [0x202f, 0x202f],
    [0x205f, 0x205f],
    [0x3000, 0x3000],
  ],
  s: SPACE_RANGES,
  v: [
    [0x0a, 0x0d],
    [0x85, 0x85],
    [0x2028, 0x2029],
  ],
  w: WORD_RANGES,
};

// Returns true when the code point is covered by the given sorted ranges.
export function codePointInRanges(ranges, codePoint) {
  for (const [from, to] of ranges) {
    if (codePoint >= from && codePoint <= to) return true;
  }

  return false;
}

// Returns true when the code point is a word char (\w): an ASCII digit,
// letter or underscore.
export function isWordCodePoint(codePoint) {
  return codePointInRanges(WORD_RANGES, codePoint);
}

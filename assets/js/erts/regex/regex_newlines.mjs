"use strict";

// Newline conventions with a two-char CR LF sequence.
export const NEWLINE_PAIR_CONVENTIONS = new Set(["any", "anycrlf", "crlf"]);

// Single chars matched by \R, by bsr mode. The bsr modes are a separate
// PCRE2 concept from the newline conventions, but each matches the same
// char set as its like-named convention.
export const NEWLINE_SEQUENCE_SINGLES = {
  anycrlf: NEWLINE_SINGLES.anycrlf,
  unicode: NEWLINE_SINGLES.any,
};

// Single chars that alone form a complete newline, per convention.
export const NEWLINE_SINGLES = {
  any: [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029],
  anycrlf: [0x0a, 0x0d],
  cr: [0x0d],
  crlf: [],
  lf: [0x0a],
  nul: [0x00],
};

// Start-of-pattern verbs that select a newline convention.
export const NEWLINE_VERBS = {
  ANY: "any",
  ANYCRLF: "anycrlf",
  CR: "cr",
  CRLF: "crlf",
  LF: "lf",
  NUL: "nul",
};

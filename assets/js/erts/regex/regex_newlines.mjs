"use strict";

// Newline conventions with a two-char CR LF sequence.
export const NEWLINE_PAIR_CONVENTIONS = new Set(["any", "anycrlf", "crlf"]);

// Single chars matched by \R, by bsr mode. The bsr modes are a separate
// PCRE2 concept from the newline conventions, but unicode mode matches the
// same char set as the "any" convention in NEWLINE_SINGLES, and anycrlf
// mode the same set as the "anycrlf" convention.
export const NEWLINE_SEQUENCE_SINGLES = {
  anycrlf: [0x0a, 0x0d],
  unicode: [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029],
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

// Returns the length of the newline sequence starting at the position,
// or 0 when there is none.
export function newlineLengthAt(newlineType, text, position) {
  if (
    NEWLINE_PAIR_CONVENTIONS.has(newlineType) &&
    text.charCodeAt(position) === 0x0d &&
    text.charCodeAt(position + 1) === 0x0a
  ) {
    return 2;
  }

  return NEWLINE_SINGLES[newlineType].includes(text.charCodeAt(position))
    ? 1
    : 0;
}

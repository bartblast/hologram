"use strict";

// Raised when the pattern source is not valid PCRE syntax.
// The position is the index of the offending character in the pattern source.
export default class RegexParseError extends Error {
  constructor(message, position) {
    super(message);
    this.name = "RegexParseError";
    this.position = position;
  }
}

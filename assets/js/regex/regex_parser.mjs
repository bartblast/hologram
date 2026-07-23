"use strict";

import RegexParseError from "./regex_parse_error.mjs";

export default class RegexParser {
  // TODO: shrink as remaining pattern constructs (escapes, classes, quantifiers, groups, anchors) are implemented
  static #unsupportedChars = new Set([
    "$",
    "(",
    ")",
    "*",
    "+",
    ".",
    "?",
    "[",
    "\\",
    "]",
    "^",
    "{",
    "}",
  ]);

  #position = 0;
  #source;

  static parse(source) {
    return new RegexParser(source).#parseAlternation();
  }

  constructor(source) {
    this.#source = source;
  }

  #atEnd() {
    return this.#position >= this.#source.length;
  }

  #parseAlternation() {
    const branches = [this.#parseConcatenation()];

    while (this.#peek() === "|") {
      this.#position++;
      branches.push(this.#parseConcatenation());
    }

    return branches.length === 1
      ? branches[0]
      : {type: "alternation", branches: branches};
  }

  #parseAtom() {
    const char = this.#peek();

    if (RegexParser.#unsupportedChars.has(char)) {
      // TODO: remove when all pattern constructs are implemented
      throw new RegexParseError(
        `unsupported pattern construct: ${char}`,
        this.#position,
      );
    }

    const codePoint = this.#source.codePointAt(this.#position);
    this.#position += codePoint > 0xffff ? 2 : 1;

    return {type: "literal", codePoint: codePoint};
  }

  #parseConcatenation() {
    const items = [];

    while (!this.#atEnd() && this.#peek() !== "|") {
      items.push(this.#parseAtom());
    }

    return items.length === 1
      ? items[0]
      : {type: "concatenation", items: items};
  }

  #peek() {
    return this.#source[this.#position];
  }
}

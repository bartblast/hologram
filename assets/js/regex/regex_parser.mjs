"use strict";

import RegexParseError from "./regex_parse_error.mjs";

// The maximum repetition count allowed in a {} quantifier by PCRE2.
const MAX_QUANTIFIER_BOUND = 65535;

export default class RegexParser {
  // TODO: shrink as remaining pattern constructs (escapes, classes, groups, anchors) are implemented
  static #unsupportedChars = new Set(["$", "(", ")", ".", "[", "\\", "]", "^"]);

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

  #isDigit(char) {
    return char >= "0" && char <= "9";
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
      const quantifier = this.#tryParseQuantifier();

      if (quantifier === null) {
        items.push(this.#parseAtom());
        continue;
      }

      const lastItem = items.at(-1);

      if (lastItem === undefined || lastItem.type === "quantifier") {
        throw new RegexParseError(
          "quantifier does not follow a repeatable item",
          this.#position,
        );
      }

      items[items.length - 1] = {
        type: "quantifier",
        min: quantifier.min,
        max: quantifier.max,
        mode: quantifier.mode,
        item: lastItem,
      };
    }

    return items.length === 1
      ? items[0]
      : {type: "concatenation", items: items};
  }

  #peek() {
    return this.#source[this.#position];
  }

  // Scans a {n}, {n,}, {n,m} or {,m} bounds spec.
  // Returns null (without consuming) when the braces don't form a valid spec,
  // in which case { is a literal, matching PCRE2 behavior.
  #tryParseBraceBounds() {
    const source = this.#source;
    let scanPosition = this.#position + 1;

    const minStart = scanPosition;
    while (this.#isDigit(source[scanPosition])) scanPosition++;
    const minDigitCount = scanPosition - minStart;

    let hasComma = false;
    if (source[scanPosition] === ",") {
      hasComma = true;
      scanPosition++;
    }

    const maxStart = scanPosition;
    while (this.#isDigit(source[scanPosition])) scanPosition++;
    const maxDigitCount = scanPosition - maxStart;

    if (source[scanPosition] !== "}") return null;

    if (minDigitCount === 0 && !(hasComma && maxDigitCount > 0)) return null;

    const min =
      minDigitCount > 0
        ? Number(source.slice(minStart, minStart + minDigitCount))
        : 0;

    if (min > MAX_QUANTIFIER_BOUND) {
      throw new RegexParseError(
        "number too big in {} quantifier",
        minStart + minDigitCount,
      );
    }

    let max;

    if (!hasComma) {
      max = min;
    } else if (maxDigitCount === 0) {
      max = null;
    } else {
      max = Number(source.slice(maxStart, scanPosition));

      if (max > MAX_QUANTIFIER_BOUND) {
        throw new RegexParseError(
          "number too big in {} quantifier",
          scanPosition,
        );
      }

      if (min > max) {
        throw new RegexParseError(
          "numbers out of order in {} quantifier",
          scanPosition,
        );
      }
    }

    this.#position = scanPosition + 1;

    return {min: min, max: max};
  }

  #tryParseQuantifier() {
    const char = this.#peek();
    let bounds;

    if (char === "*") {
      bounds = {min: 0, max: null};
      this.#position++;
    } else if (char === "+") {
      bounds = {min: 1, max: null};
      this.#position++;
    } else if (char === "?") {
      bounds = {min: 0, max: 1};
      this.#position++;
    } else if (char === "{") {
      bounds = this.#tryParseBraceBounds();
      if (bounds === null) return null;
    } else {
      return null;
    }

    let mode = "greedy";

    if (this.#peek() === "?") {
      mode = "lazy";
      this.#position++;
    } else if (this.#peek() === "+") {
      mode = "possessive";
      this.#position++;
    }

    return {min: bounds.min, max: bounds.max, mode: mode};
  }
}

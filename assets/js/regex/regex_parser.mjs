"use strict";

import RegexParseError from "./regex_parse_error.mjs";

// The maximum repetition count allowed in a {} quantifier by PCRE2.
const MAX_QUANTIFIER_BOUND = 65535;

// The class names recognized by PCRE2 in [:name:] POSIX class elements.
const POSIX_CLASS_NAMES = new Set([
  "alnum",
  "alpha",
  "ascii",
  "blank",
  "cntrl",
  "digit",
  "graph",
  "lower",
  "print",
  "punct",
  "space",
  "upper",
  "word",
  "xdigit",
]);

export default class RegexParser {
  // TODO: shrink as remaining pattern constructs (escapes, groups, anchors) are implemented
  static #unsupportedChars = new Set(["$", "(", ")", ".", "\\", "^"]);

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

  #isPosixNameChar(char) {
    return (
      (char >= "a" && char <= "z") ||
      (char >= "A" && char <= "Z") ||
      this.#isDigit(char)
    );
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

    if (char === "[") return this.#parseCharacterClass();

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

  #parseCharacterClass() {
    this.#position++;

    this.#raiseIfPosixClassOutsideClass();

    let negated = false;

    if (this.#peek() === "^") {
      negated = true;
      this.#position++;
    }

    const items = [];
    let isFirstItem = true;

    while (true) {
      if (this.#atEnd()) {
        throw new RegexParseError(
          "missing terminating ] for character class",
          this.#position,
        );
      }

      const char = this.#peek();

      // ] is a literal member when it's the first item, matching PCRE2 behavior
      if (char === "]" && !isFirstItem) {
        this.#position++;
        break;
      }

      isFirstItem = false;

      if (char === "\\") {
        // TODO: remove when escapes inside character classes are implemented
        throw new RegexParseError(
          `unsupported pattern construct: ${char}`,
          this.#position,
        );
      }

      if (char === "[" && this.#source[this.#position + 1] === ":") {
        const posixClass = this.#tryParsePosixClass();

        if (posixClass !== null) {
          items.push(posixClass);
          continue;
        }
      }

      items.push(this.#parseClassCharOrRange());
    }

    return {type: "class", negated: negated, items: items};
  }

  #parseClassCharOrRange() {
    const from = this.#source.codePointAt(this.#position);
    this.#position += from > 0xffff ? 2 : 1;

    // - forms a range only between two members; before ] or at pattern end it's a literal
    if (
      this.#peek() !== "-" ||
      this.#source[this.#position + 1] === "]" ||
      this.#position + 1 >= this.#source.length
    ) {
      return {type: "literal", codePoint: from};
    }

    this.#position++;

    if (this.#peek() === "\\") {
      // TODO: remove when escapes inside character classes are implemented
      throw new RegexParseError(
        `unsupported pattern construct: \\`,
        this.#position,
      );
    }

    if (
      this.#peek() === "[" &&
      this.#source[this.#position + 1] === ":" &&
      this.#tryParsePosixClass() !== null
    ) {
      throw new RegexParseError(
        "invalid range in character class",
        this.#position,
      );
    }

    const to = this.#source.codePointAt(this.#position);
    this.#position += to > 0xffff ? 2 : 1;

    if (to < from) {
      throw new RegexParseError(
        "range out of order in character class",
        this.#position,
      );
    }

    return {type: "range", from: from, to: to};
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

  // Detects the common mistake of using [:name:] as a whole class,
  // e.g. [:alpha:] instead of [[:alpha:]], matching PCRE2 behavior.
  #raiseIfPosixClassOutsideClass() {
    if (this.#peek() !== ":") return;

    let scanPosition = this.#position + 1;

    if (this.#source[scanPosition] === "^") scanPosition++;

    while (this.#isPosixNameChar(this.#source[scanPosition])) scanPosition++;

    if (
      this.#source[scanPosition] === ":" &&
      this.#source[scanPosition + 1] === "]"
    ) {
      throw new RegexParseError(
        "POSIX named classes are supported only within a class",
        scanPosition + 2,
      );
    }
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

  // Scans a [:name:] or [:^name:] POSIX class element.
  // Returns null (without consuming) when the syntax doesn't form a POSIX
  // element, in which case [ is a literal class member, matching PCRE2 behavior.
  #tryParsePosixClass() {
    let scanPosition = this.#position + 2;
    let negated = false;

    if (this.#source[scanPosition] === "^") {
      negated = true;
      scanPosition++;
    }

    const nameStart = scanPosition;

    while (this.#isPosixNameChar(this.#source[scanPosition])) scanPosition++;

    if (
      this.#source[scanPosition] !== ":" ||
      this.#source[scanPosition + 1] !== "]"
    ) {
      return null;
    }

    const name = this.#source.slice(nameStart, scanPosition);
    this.#position = scanPosition + 2;

    if (!POSIX_CLASS_NAMES.has(name)) {
      throw new RegexParseError("unknown POSIX class name", this.#position);
    }

    return {type: "posixClass", name: name, negated: negated};
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

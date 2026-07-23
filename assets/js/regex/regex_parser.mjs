"use strict";

import RegexParseError from "./regex_parse_error.mjs";

// Simple single-character escapes valid in all contexts.
const CHAR_ESCAPE_CODE_POINTS = {
  a: 7,
  e: 27,
  f: 12,
  n: 10,
  r: 13,
  t: 9,
};

// Anchor and simple assertion escapes outside character classes.
const ESCAPE_ANCHOR_KINDS = {
  A: "subjectStart",
  B: "nonWordBoundary",
  G: "matchStart",
  Z: "subjectEndBeforeFinalNewline",
  b: "wordBoundary",
  z: "subjectEnd",
};

// TODO: shrink as remaining escape sequences (backreferences, Unicode
// properties, \Q...\E) are implemented
const FUTURE_CLASS_ESCAPES = new Set([..."EPQp"]);

// TODO: shrink as remaining escape sequences (backreferences, subroutine
// references, Unicode properties, \K, \Q...\E) are implemented
const FUTURE_TOP_LEVEL_ESCAPES = new Set([..."EKPQgkp123456789"]);

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

// Shorthand character class escape letters, in both cases
// (uppercase means negated).
const SHORTHAND_CLASS_LETTERS = new Set([..."DHSVWdhsvw"]);

// Escape letters PCRE2 rejects with a dedicated message.
const UNSUPPORTED_BY_PCRE2_ESCAPES = new Set(["F", "L", "U", "l", "u"]);

export default class RegexParser {
  #dupnames;
  #groupCount = 0;
  #groupNames = new Set();
  #noAutoCapture;
  #position = 0;
  #source;
  #unicode;

  static parse(source, opts = {}) {
    return new RegexParser(source, opts).#parsePattern();
  }

  constructor(source, opts = {}) {
    this.#dupnames = opts.dupnames === true;
    this.#noAutoCapture = opts.noAutoCapture === true;
    this.#source = source;
    this.#unicode = opts.unicode === true;
  }

  #atEnd() {
    return this.#position >= this.#source.length;
  }

  #buildShorthand(letter) {
    const isNegated = letter >= "A" && letter <= "Z";

    return {
      type: "shorthand",
      letter: letter.toLowerCase(),
      negated: isNegated,
    };
  }

  // Returns the maximum number of characters a node can match,
  // or null when the length is unbounded.
  #calculateMaxBranchLength(node) {
    switch (node.type) {
      case "alternation": {
        let max = 0;

        for (const branch of node.branches) {
          const branchMax = this.#calculateMaxBranchLength(branch);
          if (branchMax === null) return null;
          if (branchMax > max) max = branchMax;
        }

        return max;
      }

      case "anchor":
      case "lookaround":
        return 0;

      case "atomicGroup":
      case "group":
      case "nonCapturingGroup":
        return this.#calculateMaxBranchLength(node.content);

      case "concatenation": {
        let sum = 0;

        for (const item of node.items) {
          const itemMax = this.#calculateMaxBranchLength(item);
          if (itemMax === null) return null;
          sum += itemMax;
        }

        return sum;
      }

      case "newlineSequence":
        return 2;

      case "quantifier": {
        if (node.max === null) return null;

        const itemMax = this.#calculateMaxBranchLength(node.item);

        return itemMax === null ? null : itemMax * node.max;
      }

      default:
        return 1;
    }
  }

  // Validates a code point produced by a \x{}, \o{} or \N{U+} escape,
  // raising at the current position (just past the digits).
  #checkCodePointValue(value) {
    const maxCodePoint = this.#unicode ? 0x10ffff : 0xff;

    if (value > maxCodePoint) {
      throw new RegexParseError(
        "character code point value in \\x{} or \\o{} is too large",
        this.#position,
      );
    }

    if (this.#unicode && value >= 0xd800 && value <= 0xdfff) {
      throw new RegexParseError(
        "disallowed Unicode code point (>= 0xd800 && <= 0xdfff)",
        this.#position,
      );
    }
  }

  // Enforces PCRE2 lookbehind length limits, raising at the position
  // of the lookbehind's opening parenthesis.
  #checkLookbehindLength(content, position) {
    const branches =
      content.type === "alternation" ? content.branches : [content];

    for (const branch of branches) {
      const maxLength = this.#calculateMaxBranchLength(branch);

      if (maxLength === null) {
        throw new RegexParseError(
          "length of lookbehind assertion is not limited",
          position,
        );
      }

      if (maxLength > 255) {
        throw new RegexParseError(
          "branch too long in variable-length lookbehind assertion",
          position,
        );
      }
    }
  }

  #isAlphanumeric(char) {
    return (
      (char >= "a" && char <= "z") ||
      (char >= "A" && char <= "Z") ||
      this.#isDigit(char)
    );
  }

  #isDigit(char) {
    return char >= "0" && char <= "9";
  }

  #isHexDigit(char) {
    return (
      this.#isDigit(char) ||
      (char >= "a" && char <= "f") ||
      (char >= "A" && char <= "F")
    );
  }

  #isOctalDigit(char) {
    return char >= "0" && char <= "7";
  }

  #isPosixNameChar(char) {
    return this.#isAlphanumeric(char);
  }

  #isWordChar(char) {
    return this.#isAlphanumeric(char) || char === "_";
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

    if (char === "\\") return this.#parseEscape();

    if (char === ".") {
      this.#position++;
      return {type: "dot"};
    }

    if (char === "^") {
      this.#position++;
      return {type: "anchor", kind: "lineStart"};
    }

    if (char === "$") {
      this.#position++;
      return {type: "anchor", kind: "lineEnd"};
    }

    if (char === "(") return this.#parseGroup();

    const codePoint = this.#source.codePointAt(this.#position);
    this.#position += codePoint > 0xffff ? 2 : 1;

    return {type: "literal", codePoint: codePoint};
  }

  #parseCapturingGroup(name) {
    // Groups are numbered by opening parenthesis order
    const number = ++this.#groupCount;
    const content = this.#parseAlternation();

    this.#requireGroupClose();

    return {type: "group", number: number, name: name, content: content};
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

      if (
        char === "\\" &&
        SHORTHAND_CLASS_LETTERS.has(this.#source[this.#position + 1])
      ) {
        items.push(this.#parseClassShorthand());
        continue;
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
    const from = this.#parseClassSingleCodePoint();

    // - forms a range only between two members; before ] or at pattern end it's a literal
    if (
      this.#peek() !== "-" ||
      this.#source[this.#position + 1] === "]" ||
      this.#position + 1 >= this.#source.length
    ) {
      return {type: "literal", codePoint: from};
    }

    this.#position++;

    if (
      this.#peek() === "\\" &&
      SHORTHAND_CLASS_LETTERS.has(this.#source[this.#position + 1])
    ) {
      this.#position += 2;
      throw new RegexParseError(
        "invalid range in character class",
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

    const to = this.#parseClassSingleCodePoint();

    if (to < from) {
      throw new RegexParseError(
        "range out of order in character class",
        this.#position,
      );
    }

    return {type: "range", from: from, to: to};
  }

  // Parses a shorthand class escape used as a class member, with the position
  // at the backslash. A - following it forms an invalid range unless it's a
  // literal before ], matching PCRE2 behavior.
  #parseClassShorthand() {
    const letter = this.#source[this.#position + 1];
    this.#position += 2;

    if (
      this.#peek() === "-" &&
      this.#source[this.#position + 1] !== "]" &&
      this.#position + 1 < this.#source.length
    ) {
      this.#position++;
      throw new RegexParseError(
        "invalid range in character class",
        this.#position,
      );
    }

    return this.#buildShorthand(letter);
  }

  // Parses a single class member char, either plain or produced by an escape.
  #parseClassSingleCodePoint() {
    if (this.#peek() !== "\\") {
      const codePoint = this.#source.codePointAt(this.#position);
      this.#position += codePoint > 0xffff ? 2 : 1;

      return codePoint;
    }

    this.#position++;

    if (this.#atEnd()) {
      throw new RegexParseError("\\ at end of pattern", this.#position);
    }

    const char = this.#peek();

    if (char === "N") {
      this.#position++;
      throw new RegexParseError(
        "\\N is not supported in a class",
        this.#position,
      );
    }

    if (char === "R") {
      this.#position++;
      throw new RegexParseError(
        "escape sequence is invalid in character class",
        this.#position,
      );
    }

    const codePoint = this.#tryParseCharEscapeCodePoint(true);

    if (codePoint !== null) return codePoint;

    this.#raiseEscapeError(true);
  }

  #parseConcatenation() {
    const items = [];

    while (!this.#atEnd() && this.#peek() !== "|" && this.#peek() !== ")") {
      const quantifier = this.#tryParseQuantifier();

      if (quantifier === null) {
        items.push(this.#parseAtom());
        continue;
      }

      const lastItem = items.at(-1);

      if (
        lastItem === undefined ||
        lastItem.type === "quantifier" ||
        lastItem.type === "anchor"
      ) {
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

  // Parses a \cx control escape, with the position just past the c.
  #parseControlEscape() {
    if (this.#atEnd()) {
      throw new RegexParseError("\\c at end of pattern", this.#position);
    }

    const codePoint = this.#source.codePointAt(this.#position);
    this.#position += codePoint > 0xffff ? 2 : 1;

    if (codePoint < 32 || codePoint > 126) {
      throw new RegexParseError(
        "\\c must be followed by a printable ASCII character",
        this.#position,
      );
    }

    const upperCased =
      codePoint >= 97 && codePoint <= 122 ? codePoint - 32 : codePoint;

    return upperCased ^ 0x40;
  }

  #parseEscape() {
    this.#position++;

    if (this.#atEnd()) {
      throw new RegexParseError("\\ at end of pattern", this.#position);
    }

    const char = this.#peek();
    const anchorKind = ESCAPE_ANCHOR_KINDS[char];

    if (anchorKind !== undefined) {
      this.#position++;
      return {type: "anchor", kind: anchorKind};
    }

    if (char === "N") return this.#parseNotNewlineEscape();

    if (SHORTHAND_CLASS_LETTERS.has(char)) {
      this.#position++;
      return this.#buildShorthand(char);
    }

    if (char === "R") {
      this.#position++;
      return {type: "newlineSequence"};
    }

    const codePoint = this.#tryParseCharEscapeCodePoint(false);

    if (codePoint !== null) return {type: "literal", codePoint: codePoint};

    this.#raiseEscapeError(false);
  }

  #parseGroup() {
    this.#position++;

    if (this.#peek() === "?") return this.#parseGroupExtension();

    if (this.#peek() === "*") {
      // TODO: remove when backtracking control verbs are implemented
      throw new RegexParseError(
        "unsupported pattern construct: (*",
        this.#position,
      );
    }

    if (this.#noAutoCapture) {
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {type: "nonCapturingGroup", content: content};
    }

    return this.#parseCapturingGroup(null);
  }

  // Parses a group form starting with (?, with the position at the ?.
  #parseGroupExtension() {
    this.#position++;

    const char = this.#peek();

    if (char === ":") {
      this.#position++;
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {type: "nonCapturingGroup", content: content};
    }

    if (char === ">") {
      this.#position++;
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {type: "atomicGroup", content: content};
    }

    if (char === "=" || char === "!") {
      this.#position++;
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {
        type: "lookaround",
        direction: "ahead",
        negated: char === "!",
        content: content,
      };
    }

    if (char === "<") {
      const nextChar = this.#source[this.#position + 1];

      if (nextChar === "=" || nextChar === "!") {
        const lookbehindStart = this.#position - 2;

        this.#position += 2;
        const content = this.#parseAlternation();
        this.#requireGroupClose();
        this.#checkLookbehindLength(content, lookbehindStart);

        return {
          type: "lookaround",
          direction: "behind",
          negated: nextChar === "!",
          content: content,
        };
      }

      this.#position++;
      return this.#parseNamedGroup(">");
    }

    if (char === "'") {
      this.#position++;
      return this.#parseNamedGroup("'");
    }

    if (char === "P") {
      const nextChar = this.#source[this.#position + 1];

      if (nextChar === "<") {
        this.#position += 2;
        return this.#parseNamedGroup(">");
      }

      if (nextChar === "=" || nextChar === ">") {
        // TODO: remove when backreferences and subroutine calls are implemented
        throw new RegexParseError(
          `unsupported pattern construct: (?P${nextChar}`,
          this.#position,
        );
      }

      this.#position += 2;
      throw new RegexParseError(
        "unrecognized character after (?P",
        this.#position,
      );
    }

    if ("#(&+-|^".includes(char) || this.#isAlphanumeric(char)) {
      // TODO: remove when conditionals, subroutine calls, inline options,
      // comments and branch reset groups are implemented
      throw new RegexParseError(
        `unsupported pattern construct: (?${char}`,
        this.#position,
      );
    }

    this.#position++;
    throw new RegexParseError(
      "unrecognized character after (? or (?-",
      this.#position,
    );
  }

  // Parses a \xhh or \x{hhh...} hex escape, with the position just past the x.
  #parseHexEscape() {
    if (this.#peek() === "{") {
      this.#position++;

      const digitsStart = this.#position;

      while (this.#isHexDigit(this.#peek())) this.#position++;

      if (this.#peek() !== "}") {
        throw new RegexParseError(
          "non-hex character in \\x{} (closing brace missing?)",
          this.#position + 1,
        );
      }

      if (this.#position === digitsStart) {
        throw new RegexParseError(
          "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
          this.#position,
        );
      }

      const value = parseInt(
        this.#source.slice(digitsStart, this.#position),
        16,
      );

      this.#checkCodePointValue(value);
      this.#position++;

      return value;
    }

    const digitsStart = this.#position;

    while (this.#position - digitsStart < 2 && this.#isHexDigit(this.#peek())) {
      this.#position++;
    }

    if (this.#position === digitsStart) {
      throw new RegexParseError(
        "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
        this.#position,
      );
    }

    return parseInt(this.#source.slice(digitsStart, this.#position), 16);
  }

  // Parses a named capturing group, with the position at the name start.
  #parseNamedGroup(terminator) {
    const nameStart = this.#position;

    if (this.#isDigit(this.#peek())) {
      this.#position++;
      throw new RegexParseError(
        "subpattern name must start with a non-digit",
        this.#position,
      );
    }

    while (this.#isWordChar(this.#peek())) this.#position++;

    const nameLength = this.#position - nameStart;

    if (nameLength === 0) {
      throw new RegexParseError("subpattern name expected", this.#position);
    }

    if (nameLength > 128) {
      throw new RegexParseError(
        "subpattern name is too long (maximum 128 code units)",
        this.#position,
      );
    }

    if (this.#peek() !== terminator) {
      throw new RegexParseError(
        "syntax error in subpattern name (missing terminator?)",
        this.#position,
      );
    }

    this.#position++;

    const name = this.#source.slice(nameStart, nameStart + nameLength);

    if (!this.#dupnames && this.#groupNames.has(name)) {
      throw new RegexParseError(
        "two named subpatterns have the same name (PCRE2_DUPNAMES not set)",
        this.#position,
      );
    }

    this.#groupNames.add(name);

    return this.#parseCapturingGroup(name);
  }

  // Parses \N (not-newline) or the \N{U+hhhh} code point form,
  // with the position at the N.
  #parseNotNewlineEscape() {
    this.#position++;

    if (this.#peek() !== "{") return {type: "notNewline"};

    this.#position++;

    if (this.#peek() !== "U" || this.#source[this.#position + 1] !== "+") {
      throw new RegexParseError(
        "PCRE2 does not support \\F, \\L, \\l, \\N{name}, \\U, or \\u",
        this.#position,
      );
    }

    this.#position += 2;

    const digitsStart = this.#position;

    while (this.#isHexDigit(this.#peek())) this.#position++;

    if (this.#peek() !== "}") {
      throw new RegexParseError(
        "non-hex character in \\x{} (closing brace missing?)",
        this.#position + 1,
      );
    }

    if (this.#position === digitsStart) {
      throw new RegexParseError(
        "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
        this.#position,
      );
    }

    const value = parseInt(this.#source.slice(digitsStart, this.#position), 16);

    if (this.#unicode) this.#checkCodePointValue(value);

    this.#position++;

    if (!this.#unicode) {
      throw new RegexParseError(
        "\\N{U+dddd} is supported only in Unicode (UTF) mode",
        this.#position,
      );
    }

    return {type: "literal", codePoint: value};
  }

  // Parses a \o{ddd...} octal escape, with the position just past the o.
  #parseOctalBraceEscape() {
    if (this.#peek() !== "{") {
      throw new RegexParseError(
        "missing opening brace after \\o",
        this.#position,
      );
    }

    this.#position++;

    const digitsStart = this.#position;

    while (this.#isOctalDigit(this.#peek())) this.#position++;

    if (this.#peek() !== "}") {
      throw new RegexParseError(
        "non-octal character in \\o{} (closing brace missing?)",
        this.#position + 1,
      );
    }

    if (this.#position === digitsStart) {
      throw new RegexParseError(
        "digits missing after \\x or in \\x{} or \\o{} or \\N{U+}",
        this.#position,
      );
    }

    const value = parseInt(this.#source.slice(digitsStart, this.#position), 8);

    this.#checkCodePointValue(value);
    this.#position++;

    return value;
  }

  // Parses an octal escape of up to 3 octal digits, with the position
  // at the first digit.
  #parseOctalEscape() {
    const digitsStart = this.#position;

    while (
      this.#position - digitsStart < 3 &&
      this.#isOctalDigit(this.#peek())
    ) {
      this.#position++;
    }

    const value = parseInt(this.#source.slice(digitsStart, this.#position), 8);

    if (!this.#unicode && value > 0xff) {
      throw new RegexParseError(
        "octal value is greater than \\377 in 8-bit non-UTF-8 mode",
        this.#position,
      );
    }

    return value;
  }

  #parsePattern() {
    const node = this.#parseAlternation();

    // Only an unmatched ) can stop the top-level alternation before the end
    if (!this.#atEnd()) {
      this.#position++;
      throw new RegexParseError(
        "unmatched closing parenthesis",
        this.#position,
      );
    }

    return node;
  }

  #peek() {
    return this.#source[this.#position];
  }

  // Raises the error PCRE2 produces for an escape with no valid meaning,
  // with the position at the escape char.
  #raiseEscapeError(inClass) {
    const char = this.#peek();

    if (UNSUPPORTED_BY_PCRE2_ESCAPES.has(char)) {
      this.#position++;
      throw new RegexParseError(
        "PCRE2 does not support \\F, \\L, \\l, \\N{name}, \\U, or \\u",
        this.#position,
      );
    }

    const futureEscapes = inClass
      ? FUTURE_CLASS_ESCAPES
      : FUTURE_TOP_LEVEL_ESCAPES;

    if (futureEscapes.has(char)) {
      // TODO: remove when remaining escape sequences are implemented
      throw new RegexParseError(
        `unsupported pattern construct: \\${char}`,
        this.#position,
      );
    }

    this.#position++;
    throw new RegexParseError(
      "unrecognized character follows \\",
      this.#position,
    );
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

  #requireGroupClose() {
    if (this.#peek() !== ")") {
      throw new RegexParseError("missing closing parenthesis", this.#position);
    }

    this.#position++;
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

  // Parses an escape that produces a single code point, with the position
  // at the escape char. Returns null (without consuming) for escapes with
  // other meanings.
  #tryParseCharEscapeCodePoint(inClass) {
    const char = this.#peek();
    const simpleCodePoint = CHAR_ESCAPE_CODE_POINTS[char];

    if (simpleCodePoint !== undefined) {
      this.#position++;
      return simpleCodePoint;
    }

    if (char === "x") {
      this.#position++;
      return this.#parseHexEscape();
    }

    if (char === "o") {
      this.#position++;
      return this.#parseOctalBraceEscape();
    }

    if (char === "c") {
      this.#position++;
      return this.#parseControlEscape();
    }

    if (inClass) {
      // \b is a backspace inside a class
      if (char === "b") {
        this.#position++;
        return 8;
      }

      // \8 and \9 are literal digits inside a class
      if (char === "8" || char === "9") {
        this.#position++;
        return char.codePointAt(0);
      }

      if (this.#isOctalDigit(char)) return this.#parseOctalEscape();
    } else if (char === "0") {
      return this.#parseOctalEscape();
    }

    if (!this.#isAlphanumeric(char)) {
      const codePoint = this.#source.codePointAt(this.#position);
      this.#position += codePoint > 0xffff ? 2 : 1;

      return codePoint;
    }

    return null;
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

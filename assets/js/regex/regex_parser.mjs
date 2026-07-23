"use strict";

import RegexParseError from "./regex_parse_error.mjs";

// TODO: remove when alpha assertions ((*atomic:...), (*pla:...), ...)
// are implemented
const ALPHA_ASSERTIONS = new Set([
  "asr",
  "atomic",
  "atomic_script_run",
  "napla",
  "naplb",
  "negative_lookahead",
  "negative_lookbehind",
  "nla",
  "nlb",
  "pla",
  "plb",
  "positive_lookahead",
  "positive_lookbehind",
  "script_run",
  "sr",
]);

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

// TODO: shrink as remaining escape sequences (Unicode properties, \Q...\E)
// are implemented
const FUTURE_TOP_LEVEL_ESCAPES = new Set([..."EPQp"]);

// The maximum repetition count allowed in a {} quantifier by PCRE2.
const MAX_QUANTIFIER_BOUND = 65535;

// TODO: remove when start-of-pattern option verbs ((*UTF), (*CR), ...)
// are implemented
const OPTION_VERBS = new Set([
  "ANY",
  "ANYCRLF",
  "BSR_ANYCRLF",
  "BSR_UNICODE",
  "CR",
  "CRLF",
  "LF",
  "LIMIT_DEPTH",
  "LIMIT_HEAP",
  "LIMIT_MATCH",
  "NO_AUTO_POSSESS",
  "NO_DOTSTAR_ANCHOR",
  "NO_JIT",
  "NO_START_OPT",
  "NOTEMPTY",
  "NOTEMPTY_ATSTART",
  "NUL",
  "UCP",
  "UTF",
]);

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

// Backtracking control verb words and the verb kinds they map to.
const VERB_KINDS = {
  ACCEPT: "accept",
  COMMIT: "commit",
  F: "fail",
  FAIL: "fail",
  MARK: "mark",
  PRUNE: "prune",
  SKIP: "skip",
  THEN: "then",
};

export default class RegexParser {
  #allGroupNames = null;
  #dupnames;
  #groupCount = 0;
  #groupNames = new Set();
  #noAutoCapture;
  #position = 0;
  #source;
  #totalGroups = null;
  #unicode;

  // Parsing is done in two passes, because PCRE2 allows forward references:
  // whether \12 is a backreference or an octal escape depends on the total
  // number of capture groups in the whole pattern. The first (lenient) pass
  // only collects the group count and names, the second pass builds the AST.
  static parse(source, opts = {}) {
    const prescanner = new RegexParser(source, opts);
    prescanner.#parsePattern();

    const parser = new RegexParser(source, opts);
    parser.#allGroupNames = prescanner.#groupNames;
    parser.#totalGroups = prescanner.#groupCount;

    return parser.#parsePattern();
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
        lastItem.type === "anchor" ||
        lastItem.type === "verb" ||
        lastItem.type === "matchStartReset"
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

  // Parses the condition of a conditional group, with the position just past
  // the condition's opening parenthesis.
  #parseCondition(conditionOpenPosition) {
    if (this.#atEnd()) {
      throw new RegexParseError("missing closing parenthesis", this.#position);
    }

    const char = this.#peek();

    // Assertion condition: the condition parentheses are the assertion's own
    if (char === "?") {
      const assertion = this.#parseGroupExtension();

      if (assertion.type !== "lookaround") {
        throw new RegexParseError(
          "assertion expected after (?( or (?(?C)",
          conditionOpenPosition,
        );
      }

      return {kind: "assertion", assertion: assertion};
    }

    // Numeric condition, absolute or relative
    if (
      this.#isDigit(char) ||
      ((char === "+" || char === "-") &&
        this.#isDigit(this.#source[this.#position + 1]))
    ) {
      const isRelative = !this.#isDigit(char);
      const signPosition = this.#position;
      const number = this.#parseSubroutineNumber();

      if (this.#peek() !== ")") {
        throw new RegexParseError(
          "missing closing parenthesis for condition",
          this.#position,
        );
      }

      this.#position++;

      if (isRelative && number <= 0) {
        throw new RegexParseError(
          "reference to non-existent subpattern",
          signPosition,
        );
      }

      this.#validateNumericReference(
        number,
        isRelative ? signPosition : conditionOpenPosition,
      );

      return {kind: "group", number: number, name: null};
    }

    // Delimited name condition
    if (char === "<" || char === "'") {
      const terminator = char === "<" ? ">" : "'";

      this.#position++;

      const {name, nameStart} = this.#parseSubpatternName(terminator);

      if (this.#peek() !== ")") {
        throw new RegexParseError(
          "missing closing parenthesis for condition",
          this.#position,
        );
      }

      this.#position++;
      this.#validateNamedReference(name, nameStart);

      return {kind: "group", number: null, name: name};
    }

    // Bare word: DEFINE, an R recursion form, or a plain group name
    const wordStart = this.#position;

    while (this.#isWordChar(this.#peek())) this.#position++;

    const word = this.#source.slice(wordStart, this.#position);

    if (word === "DEFINE" && this.#peek() === ")") {
      this.#position++;
      return {kind: "define"};
    }

    if (word === "R" && this.#peek() === ")") {
      this.#position++;
      return {kind: "recursion", number: null, name: null};
    }

    if (word === "R" && this.#peek() === "&") {
      this.#position++;

      const {name, nameStart} = this.#parseSubpatternName(")");
      this.#validateNamedReference(name, nameStart);

      return {kind: "recursion", number: null, name: name};
    }

    if (/^R\d+$/.test(word) && this.#peek() === ")") {
      const number = Number(word.slice(1));

      this.#position++;
      this.#validateNumericReference(number, wordStart);

      return {kind: "recursion", number: number, name: null};
    }

    if (word === "VERSION") {
      // TODO: remove when VERSION conditions are implemented
      throw new RegexParseError(
        "unsupported pattern construct: (?(VERSION",
        wordStart,
      );
    }

    if (word.length === 0) {
      throw new RegexParseError(
        "assertion expected after (?( or (?(?C)",
        conditionOpenPosition,
      );
    }

    if (this.#peek() !== ")") {
      throw new RegexParseError(
        "syntax error in subpattern name (missing terminator?)",
        this.#position,
      );
    }

    this.#position++;
    this.#validateNamedReference(word, wordStart);

    return {kind: "group", number: null, name: word};
  }

  // Parses a conditional group (?(condition)yes|no), with the position
  // at the condition's opening parenthesis.
  #parseConditional() {
    const conditionalStart = this.#position - 2;
    const conditionOpenPosition = this.#position;

    this.#position++;

    const condition = this.#parseCondition(conditionOpenPosition);
    const content = this.#parseAlternation();

    this.#requireGroupClose();

    const branches =
      content.type === "alternation" ? content.branches : [content];

    if (condition.kind === "define") {
      if (branches.length > 1) {
        throw new RegexParseError(
          "DEFINE subpattern contains more than one branch",
          conditionOpenPosition + 1,
        );
      }
    } else if (branches.length > 2) {
      throw new RegexParseError(
        "conditional subpattern contains more than two branches",
        conditionalStart,
      );
    }

    return {
      type: "conditional",
      condition: condition,
      yes: branches[0],
      no: branches.length > 1 ? branches[1] : null,
    };
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

  // Parses a \ddd escape starting with a non-zero digit, with the position at
  // the first digit. Such an escape is a backreference when the group exists,
  // an octal character escape as a fallback, matching PCRE2 behavior.
  #parseDigitEscape() {
    const digitsStart = this.#position;

    while (this.#isDigit(this.#peek())) this.#position++;

    const digits = this.#source.slice(digitsStart, this.#position);
    const number = Number(digits);

    // Lenient prescan pass: the total group count isn't known yet
    if (this.#totalGroups === null) {
      return {type: "backreference", number: number, name: null};
    }

    if (number <= this.#totalGroups) {
      return {type: "backreference", number: number, name: null};
    }

    // A single-digit escape is always a backreference
    if (digits.length === 1) {
      throw new RegexParseError(
        "reference to non-existent subpattern",
        this.#position,
      );
    }

    // Octal fallback: re-read as an octal escape plus literal digits
    if (digits[0] <= "7") {
      this.#position = digitsStart;
      return {type: "literal", codePoint: this.#parseOctalEscape()};
    }

    throw new RegexParseError(
      "reference to non-existent subpattern",
      this.#position,
    );
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

    if (this.#isDigit(char) && char !== "0") return this.#parseDigitEscape();

    if (char === "g") return this.#parseGReference();

    if (char === "k") return this.#parseKReference();

    if (char === "K") {
      this.#position++;
      return {type: "matchStartReset"};
    }

    const codePoint = this.#tryParseCharEscapeCodePoint(false);

    if (codePoint !== null) return {type: "literal", codePoint: codePoint};

    this.#raiseEscapeError(false);
  }

  // Parses a \g reference (\gn, \g{n}, \g{-n}, \g{+n} or \g{name}),
  // with the position at the g.
  #parseGReference() {
    this.#position++;

    const afterG = this.#position;

    if (this.#isDigit(this.#peek())) {
      const digitsStart = this.#position;

      while (this.#isDigit(this.#peek())) this.#position++;

      const number = Number(this.#source.slice(digitsStart, this.#position));
      this.#validateNumericReference(number, this.#position);

      return {type: "backreference", number: number, name: null};
    }

    if (this.#peek() === "{") {
      this.#position++;

      const sign = this.#peek();

      if (sign === "-" || sign === "+") {
        this.#position++;

        const digitsStart = this.#position;

        while (this.#isDigit(this.#peek())) this.#position++;

        if (this.#position === digitsStart) {
          throw new RegexParseError("subpattern name expected", this.#position);
        }

        const offset = Number(this.#source.slice(digitsStart, this.#position));

        // Relative references resolve against the groups opened so far
        const number =
          sign === "-"
            ? this.#groupCount + 1 - offset
            : this.#groupCount + offset;

        if (this.#peek() !== "}") {
          throw new RegexParseError(
            "syntax error in subpattern name (missing terminator?)",
            this.#position,
          );
        }

        this.#position++;

        if (number <= 0) {
          throw new RegexParseError(
            "reference to non-existent subpattern",
            afterG,
          );
        }

        this.#validateNumericReference(number, this.#position);

        return {type: "backreference", number: number, name: null};
      }

      if (this.#isDigit(sign)) {
        const digitsStart = this.#position;

        while (this.#isDigit(this.#peek())) this.#position++;

        const number = Number(this.#source.slice(digitsStart, this.#position));

        if (this.#peek() !== "}") {
          throw new RegexParseError(
            "syntax error in subpattern name (missing terminator?)",
            this.#position,
          );
        }

        this.#position++;
        this.#validateNumericReference(number, this.#position);

        return {type: "backreference", number: number, name: null};
      }

      const {name, nameStart} = this.#parseSubpatternName("}");
      this.#validateNamedReference(name, nameStart);

      return {type: "backreference", number: null, name: name};
    }

    if (this.#peek() === "<" || this.#peek() === "'") {
      const terminator = this.#peek() === "<" ? ">" : "'";

      this.#position++;

      const next = this.#peek();

      if (
        this.#isDigit(next) ||
        ((next === "+" || next === "-") &&
          this.#isDigit(this.#source[this.#position + 1]))
      ) {
        const isRelative = !this.#isDigit(next);
        const number = this.#parseSubroutineNumber();

        if (this.#peek() !== terminator) {
          throw new RegexParseError(
            "syntax error in subpattern number (missing terminator?)",
            this.#position,
          );
        }

        this.#position++;

        if (isRelative && number <= 0) {
          throw new RegexParseError(
            "reference to non-existent subpattern",
            this.#position,
          );
        }

        if (number > 0) this.#validateNumericReference(number, this.#position);

        return {type: "subroutine", number: number, name: null};
      }

      const {name, nameStart} = this.#parseSubpatternName(terminator);
      this.#validateNamedReference(name, nameStart);

      return {type: "subroutine", number: null, name: name};
    }

    throw new RegexParseError(
      "\\g is not followed by a braced, angle-bracketed, or quoted name/number or by a plain number",
      afterG,
    );
  }

  #parseGroup() {
    this.#position++;

    if (this.#peek() === "?") return this.#parseGroupExtension();

    if (this.#peek() === "*") return this.#parseVerb();

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

      if (nextChar === "=") {
        this.#position += 2;

        const {name, nameStart} = this.#parseSubpatternName(")");
        this.#validateNamedReference(name, nameStart);

        return {type: "backreference", number: null, name: name};
      }

      if (nextChar === ">") {
        this.#position += 2;

        const {name, nameStart} = this.#parseSubpatternName(")");
        this.#validateNamedReference(name, nameStart);

        return {type: "subroutine", number: null, name: name};
      }

      this.#position += 2;
      throw new RegexParseError(
        "unrecognized character after (?P",
        this.#position,
      );
    }

    if (char === "R") {
      this.#position++;

      if (this.#peek() !== ")") {
        throw new RegexParseError(
          "(?R (recursive pattern call) must be followed by a closing parenthesis",
          this.#position,
        );
      }

      this.#position++;

      return {type: "subroutine", number: 0, name: null};
    }

    if (
      this.#isDigit(char) ||
      ((char === "+" || char === "-") &&
        this.#isDigit(this.#source[this.#position + 1]))
    ) {
      const isRelative = !this.#isDigit(char);
      const number = this.#parseSubroutineNumber();

      if (this.#peek() !== ")") {
        throw new RegexParseError(
          "missing closing parenthesis",
          this.#position,
        );
      }

      if (isRelative && number <= 0) {
        throw new RegexParseError(
          "reference to non-existent subpattern",
          this.#position,
        );
      }

      if (number > 0) this.#validateNumericReference(number, this.#position);

      this.#position++;

      return {type: "subroutine", number: number, name: null};
    }

    if (char === "&") {
      this.#position++;

      const {name, nameStart} = this.#parseSubpatternName(")");
      this.#validateNamedReference(name, nameStart);

      return {type: "subroutine", number: null, name: name};
    }

    if (char === "(") return this.#parseConditional();

    if ("#+-|^".includes(char) || this.#isAlphanumeric(char)) {
      // TODO: remove when inline options, comments and branch reset groups
      // are implemented
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

  // Parses a \k named reference (\k<name>, \k'name' or \k{name}),
  // with the position at the k.
  #parseKReference() {
    this.#position++;

    const delimiter = this.#peek();
    let terminator = null;

    if (delimiter === "<") terminator = ">";
    else if (delimiter === "'") terminator = "'";
    else if (delimiter === "{") terminator = "}";

    if (terminator === null) {
      throw new RegexParseError(
        "\\k is not followed by a braced, angle-bracketed, or quoted name",
        this.#position,
      );
    }

    this.#position++;

    const {name, nameStart} = this.#parseSubpatternName(terminator);
    this.#validateNamedReference(name, nameStart);

    return {type: "backreference", number: null, name: name};
  }

  // Parses a named capturing group, with the position at the name start.
  #parseNamedGroup(terminator) {
    const {name} = this.#parseSubpatternName(terminator);

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

  // Parses a subpattern name followed by the given terminator,
  // with the position at the name start.
  #parseSubpatternName(terminator) {
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

    return {
      name: this.#source.slice(nameStart, nameStart + nameLength),
      nameStart: nameStart,
    };
  }

  // Scans an optional +/- sign and digits, resolving relative numbers
  // against the groups opened so far, with the position at the sign or
  // first digit.
  #parseSubroutineNumber() {
    const char = this.#peek();
    const sign = char === "+" || char === "-" ? char : null;

    if (sign !== null) this.#position++;

    const digitsStart = this.#position;

    while (this.#isDigit(this.#peek())) this.#position++;

    const value = Number(this.#source.slice(digitsStart, this.#position));

    if (sign === "-") return this.#groupCount + 1 - value;
    if (sign === "+") return this.#groupCount + value;

    return value;
  }

  // Parses a (*VERB) or (*VERB:name) backtracking control verb,
  // with the position at the *.
  #parseVerb() {
    const asteriskPosition = this.#position;

    this.#position++;

    const wordStart = this.#position;

    while (this.#isWordChar(this.#peek())) this.#position++;

    const word = this.#source.slice(wordStart, this.#position);

    // (*) is parsed as a group with a misplaced quantifier, matching PCRE2
    if (word === "" && this.#peek() !== ":") {
      throw new RegexParseError(
        "quantifier does not follow a repeatable item",
        asteriskPosition + 1,
      );
    }

    const kind = word === "" ? "mark" : VERB_KINDS[word];

    if (kind === undefined) {
      if (OPTION_VERBS.has(word) || ALPHA_ASSERTIONS.has(word)) {
        // TODO: remove when option verbs and alpha assertions are implemented
        throw new RegexParseError(
          `unsupported pattern construct: (*${word}`,
          wordStart,
        );
      }

      if (/[a-z]/.test(word)) {
        throw new RegexParseError(
          "(*alpha_assertion) not recognized",
          this.#position + 1,
        );
      }

      throw new RegexParseError(
        "(*VERB) not recognized or malformed",
        this.#position,
      );
    }

    let name = null;

    if (this.#peek() === ":") {
      this.#position++;

      const nameStart = this.#position;

      while (!this.#atEnd() && this.#peek() !== ")") this.#position++;

      name = this.#source.slice(nameStart, this.#position);
    }

    if (kind === "mark" && (name === null || name === "")) {
      throw new RegexParseError(
        "(*MARK) must have an argument",
        this.#position,
      );
    }

    if (this.#peek() !== ")") {
      throw new RegexParseError(
        "(*VERB) not recognized or malformed",
        this.#position,
      );
    }

    this.#position++;

    return {type: "verb", verb: kind, name: name === "" ? null : name};
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

      // \g and \k are literal letters inside a class
      if (char === "g" || char === "k") {
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

  // Validates a named reference, raising at the name start position.
  // Skipped in the lenient prescan pass, when names aren't yet collected.
  #validateNamedReference(name, nameStart) {
    if (this.#allGroupNames !== null && !this.#allGroupNames.has(name)) {
      throw new RegexParseError(
        "reference to non-existent subpattern",
        nameStart,
      );
    }
  }

  // Validates a numeric reference, raising at the given position.
  // Skipped in the lenient prescan pass, when the group count isn't known yet.
  #validateNumericReference(number, errorPosition) {
    if (this.#totalGroups !== null && number > this.#totalGroups) {
      throw new RegexParseError(
        "reference to non-existent subpattern",
        errorPosition,
      );
    }
  }
}

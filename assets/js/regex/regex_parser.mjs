"use strict";

import RegexParseError from "./regex_parse_error.mjs";

// Alpha assertion names accepted in the (*name:...) form.
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

// Lookaround alpha assertion names and the lookarounds they map to.
const ALPHA_LOOKAROUNDS = {
  napla: {direction: "ahead", negated: false, atomic: false},
  naplb: {direction: "behind", negated: false, atomic: false},
  negative_lookahead: {direction: "ahead", negated: true, atomic: true},
  negative_lookbehind: {direction: "behind", negated: true, atomic: true},
  nla: {direction: "ahead", negated: true, atomic: true},
  nlb: {direction: "behind", negated: true, atomic: true},
  pla: {direction: "ahead", negated: false, atomic: true},
  plb: {direction: "behind", negated: false, atomic: true},
  positive_lookahead: {direction: "ahead", negated: false, atomic: true},
  positive_lookbehind: {direction: "behind", negated: false, atomic: true},
};

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

// Whitespace chars ignored in extended mode outside character classes.
const EXTENDED_WHITESPACE = new Set([" ", "\t", "\n", "\v", "\f", "\r"]);

// Unicode general category names and PCRE2 special property names,
// used to validate one- and two-letter property names.
const GENERAL_CATEGORIES = new Set([
  "Any",
  "C",
  "Cc",
  "Cf",
  "Cn",
  "Co",
  "Cs",
  "L",
  "LC",
  "Ll",
  "Lm",
  "Lo",
  "Lt",
  "Lu",
  "M",
  "Mc",
  "Me",
  "Mn",
  "N",
  "Nd",
  "Nl",
  "No",
  "P",
  "Pc",
  "Pd",
  "Pe",
  "Pf",
  "Pi",
  "Po",
  "S",
  "Sc",
  "Sk",
  "Sm",
  "So",
  "Xan",
  "Xps",
  "Xsp",
  "Xuc",
  "Xwd",
  "Z",
  "Zl",
  "Zp",
  "Zs",
]);

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

// Option verbs recognized at the start of a pattern.
// The LIMIT_ verbs take an =number value.
const START_OPTION_VERBS = new Set([
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
  "UTF8",
]);

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
  #extended;
  #extendedMore = false;
  #groupCount = 0;
  #groupNames = new Set();
  #inClassQuote = false;
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
    this.#extended = opts.extended === true;
    this.#noAutoCapture = opts.noAutoCapture === true;
    this.#source = source;
    this.#unicode = opts.unicode === true;
  }

  // Applies parse-affecting inline option letters to the parser state.
  // The i, m, s and U options only affect matching and are handled by the
  // engines from the AST.
  #applyOptionLetters(reset, set, unset) {
    // (?^ resets i, m, n, s and x to their defaults (J is unaffected)
    if (reset) {
      this.#extended = false;
      this.#extendedMore = false;
      this.#noAutoCapture = false;
    }

    if (set.includes("J")) this.#dupnames = true;
    if (set.includes("n")) this.#noAutoCapture = true;

    if (set.includes("x")) {
      this.#extended = true;
      this.#extendedMore = set.includes("xx");
    }

    if (unset.includes("J")) this.#dupnames = false;
    if (unset.includes("n")) this.#noAutoCapture = false;

    if (unset.includes("x")) {
      this.#extended = false;
      this.#extendedMore = false;
    }
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

  // Parses the content of a (*name:...) alpha assertion, with the position
  // at the colon.
  #parseAlphaAssertion(word, wordStart) {
    this.#position++;

    const content = this.#parseAlternation();

    this.#requireGroupClose();

    switch (word) {
      case "atomic":
        return {type: "atomicGroup", content: content};

      case "asr":
      case "atomic_script_run":
        return {type: "scriptRun", atomic: true, content: content};

      case "script_run":
      case "sr":
        return {type: "scriptRun", atomic: false, content: content};

      default: {
        const {direction, negated, atomic} = ALPHA_LOOKAROUNDS[word];

        if (direction === "behind") {
          this.#checkLookbehindLength(content, wordStart);
        }

        return {
          type: "lookaround",
          direction: direction,
          negated: negated,
          atomic: atomic,
          content: content,
        };
      }
    }
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

  // Parses a (?|...) branch reset group, with the position at the |.
  // Each top-level branch restarts group numbering from the same base, and
  // duplicate names are allowed across branches, matching PCRE2 behavior.
  #parseBranchReset() {
    this.#position++;

    const baseGroupCount = this.#groupCount;
    const outerNames = this.#groupNames;
    const collectedNames = new Set(outerNames);
    const branches = [];
    let maxGroupCount = baseGroupCount;

    while (true) {
      this.#groupCount = baseGroupCount;
      this.#groupNames = new Set(outerNames);

      branches.push(this.#parseConcatenation());

      if (this.#groupCount > maxGroupCount) maxGroupCount = this.#groupCount;

      for (const name of this.#groupNames) collectedNames.add(name);

      if (this.#peek() !== "|") break;

      this.#position++;
    }

    this.#groupCount = maxGroupCount;
    this.#groupNames = collectedNames;
    this.#requireGroupClose();

    const content =
      branches.length === 1
        ? branches[0]
        : {type: "alternation", branches: branches};

    return {type: "branchResetGroup", content: content};
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

    this.#inClassQuote = false;

    while (true) {
      this.#skipClassQuoteMarkers();

      // Extended-more mode ignores unescaped spaces and tabs in classes
      if (
        !this.#inClassQuote &&
        this.#extendedMore &&
        (this.#peek() === " " || this.#peek() === "\t")
      ) {
        this.#position++;
        continue;
      }

      if (this.#atEnd()) {
        throw new RegexParseError(
          "missing terminating ] for character class",
          this.#position,
        );
      }

      if (this.#inClassQuote) {
        isFirstItem = false;
        items.push(this.#parseClassCharOrRange());
        continue;
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

      if (
        char === "\\" &&
        (this.#source[this.#position + 1] === "p" ||
          this.#source[this.#position + 1] === "P")
      ) {
        this.#position++;
        items.push(this.#parseUnicodeProperty(this.#peek()));

        // A - after a property forms an invalid range unless it's a literal
        // before ], matching PCRE2 behavior
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

    this.#skipClassQuoteMarkers();

    // - forms a range only outside quoting and between two members;
    // before ] or at pattern end it's a literal
    if (
      this.#inClassQuote ||
      this.#peek() !== "-" ||
      this.#source[this.#position + 1] === "]" ||
      this.#position + 1 >= this.#source.length
    ) {
      return {type: "literal", codePoint: from};
    }

    this.#position++;

    this.#skipClassQuoteMarkers();

    if (!this.#inClassQuote) {
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
        this.#peek() === "\\" &&
        (this.#source[this.#position + 1] === "p" ||
          this.#source[this.#position + 1] === "P")
      ) {
        this.#position++;
        this.#parseUnicodeProperty(this.#peek());
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
  // Inside \Q...\E quoting every char is taken literally.
  #parseClassSingleCodePoint() {
    if (this.#inClassQuote) {
      const codePoint = this.#source.codePointAt(this.#position);
      this.#position += codePoint > 0xffff ? 2 : 1;

      return codePoint;
    }

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

    this.#raiseEscapeError();
  }

  #parseConcatenation() {
    const items = [];

    while (true) {
      if (this.#extended) this.#skipExtendedWhitespace();

      if (this.#atEnd() || this.#peek() === "|" || this.#peek() === ")") break;

      // Comments are invisible: a quantifier after one applies to the item
      // before it, matching PCRE2 behavior
      if (
        this.#peek() === "(" &&
        this.#source[this.#position + 1] === "?" &&
        this.#source[this.#position + 2] === "#"
      ) {
        this.#skipComment();
        continue;
      }

      // \Q...\E quoting: quoted chars are literal atoms, so a quantifier
      // after \E applies to the last quoted char, matching PCRE2 behavior
      if (this.#peek() === "\\" && this.#source[this.#position + 1] === "Q") {
        this.#position += 2;

        while (!this.#atEnd()) {
          if (
            this.#peek() === "\\" &&
            this.#source[this.#position + 1] === "E"
          ) {
            this.#position += 2;
            break;
          }

          const codePoint = this.#source.codePointAt(this.#position);
          this.#position += codePoint > 0xffff ? 2 : 1;
          items.push({type: "literal", codePoint: codePoint});
        }

        continue;
      }

      // \E without a preceding \Q is ignored
      if (this.#peek() === "\\" && this.#source[this.#position + 1] === "E") {
        this.#position += 2;
        continue;
      }

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

    if (word === "VERSION" && (this.#peek() === ">" || this.#peek() === "=")) {
      let gte = false;

      if (this.#peek() === ">") {
        this.#position++;

        if (this.#peek() !== "=") {
          throw new RegexParseError(
            "syntax error or number too big in (?(VERSION condition",
            this.#position,
          );
        }

        gte = true;
      }

      this.#position++;

      const majorStart = this.#position;

      while (this.#isDigit(this.#peek())) this.#position++;

      if (this.#position === majorStart) {
        throw new RegexParseError(
          "syntax error or number too big in (?(VERSION condition",
          this.#position,
        );
      }

      const major = Number(this.#source.slice(majorStart, this.#position));
      let minor = 0;

      if (this.#peek() === ".") {
        this.#position++;

        const minorStart = this.#position;

        while (this.#isDigit(this.#peek())) this.#position++;

        if (this.#position === minorStart) {
          throw new RegexParseError(
            "syntax error or number too big in (?(VERSION condition",
            this.#position,
          );
        }

        minor = Number(this.#source.slice(minorStart, this.#position));
      }

      if (this.#peek() !== ")") {
        throw new RegexParseError(
          "syntax error or number too big in (?(VERSION condition",
          this.#position,
        );
      }

      this.#position++;

      return {kind: "version", gte: gte, major: major, minor: minor};
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

    if (char === "p" || char === "P") return this.#parseUnicodeProperty(char);

    const codePoint = this.#tryParseCharEscapeCodePoint(false);

    if (codePoint !== null) return {type: "literal", codePoint: codePoint};

    this.#raiseEscapeError();
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

    if (this.#peek() === "*") return this.#parseVerb();

    const savedDupnames = this.#dupnames;
    const savedExtended = this.#extended;
    const savedExtendedMore = this.#extendedMore;
    const savedNoAutoCapture = this.#noAutoCapture;
    let node;

    if (this.#peek() === "?") {
      node = this.#parseGroupExtension();
    } else if (this.#noAutoCapture) {
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      node = {type: "nonCapturingGroup", content: content};
    } else {
      node = this.#parseCapturingGroup(null);
    }

    // Inline option settings persist to the end of the enclosing group
    if (node.type !== "optionSetting") {
      this.#dupnames = savedDupnames;
      this.#extended = savedExtended;
      this.#extendedMore = savedExtendedMore;
      this.#noAutoCapture = savedNoAutoCapture;
    }

    return node;
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
        atomic: true,
        content: content,
      };
    }

    // (?* is a non-atomic positive lookahead
    if (char === "*") {
      this.#position++;
      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {
        type: "lookaround",
        direction: "ahead",
        negated: false,
        atomic: false,
        content: content,
      };
    }

    if (char === "<") {
      const nextChar = this.#source[this.#position + 1];

      // (?<* is a non-atomic positive lookbehind
      if (nextChar === "=" || nextChar === "!" || nextChar === "*") {
        const lookbehindStart = this.#position - 2;

        this.#position += 2;
        const content = this.#parseAlternation();
        this.#requireGroupClose();
        this.#checkLookbehindLength(content, lookbehindStart);

        return {
          type: "lookaround",
          direction: "behind",
          negated: nextChar === "!",
          atomic: nextChar !== "*",
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

    if ("iJmnsUxa^-".includes(char)) return this.#parseOptionSetting();

    if (char === "|") return this.#parseBranchReset();

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

  // Parses an inline option setting (?imsx-imsx) or option group
  // (?imsx-imsx:...), incl. the (?^...) reset forms, with the position
  // at the first option char.
  #parseOptionSetting() {
    let reset = false;

    if (this.#peek() === "^") {
      reset = true;
      this.#position++;
    }

    const set = this.#scanOptionLetters();
    let unset = "";

    if (this.#peek() === "-") {
      this.#position++;

      if (reset) {
        throw new RegexParseError(
          "invalid hyphen in option setting",
          this.#position,
        );
      }

      unset = this.#scanOptionLetters();
    }

    if (this.#peek() === ":") {
      this.#position++;
      this.#applyOptionLetters(reset, set, unset);

      const content = this.#parseAlternation();
      this.#requireGroupClose();

      return {
        type: "optionGroup",
        reset: reset,
        set: set,
        unset: unset,
        content: content,
      };
    }

    if (this.#peek() === ")") {
      this.#position++;
      this.#applyOptionLetters(reset, set, unset);

      return {type: "optionSetting", reset: reset, set: set, unset: unset};
    }

    if (this.#atEnd()) {
      throw new RegexParseError("missing closing parenthesis", this.#position);
    }

    this.#position++;
    throw new RegexParseError(
      "unrecognized character after (? or (?-",
      this.#position,
    );
  }

  #parsePattern() {
    const startOptions = this.#parseStartOptions();
    const node = this.#parseAlternation();

    // Only an unmatched ) can stop the top-level alternation before the end
    if (!this.#atEnd()) {
      this.#position++;
      throw new RegexParseError(
        "unmatched closing parenthesis",
        this.#position,
      );
    }

    if (startOptions.length === 0) return node;

    const items = node.type === "concatenation" ? node.items : [node];

    return {type: "concatenation", items: [...startOptions, ...items]};
  }

  // Parses (*VERB) option settings at the start of the pattern.
  // A (* sequence that doesn't form a valid start option is left for the
  // regular verb parsing, which raises the error PCRE2 produces.
  #parseStartOptions() {
    const options = [];

    while (this.#peek() === "(" && this.#source[this.#position + 1] === "*") {
      const wordStart = this.#position + 2;
      let scanPosition = wordStart;

      while (this.#isWordChar(this.#source[scanPosition])) scanPosition++;

      const word = this.#source.slice(wordStart, scanPosition);

      if (!START_OPTION_VERBS.has(word)) break;

      let value = null;

      if (this.#source[scanPosition] === "=") {
        scanPosition++;

        const digitsStart = scanPosition;

        while (this.#isDigit(this.#source[scanPosition])) scanPosition++;

        if (scanPosition === digitsStart) break;

        value = Number(this.#source.slice(digitsStart, scanPosition));
      }

      if (this.#source[scanPosition] !== ")") break;

      // The LIMIT_ verbs require a value, the other verbs don't take one
      if (word.startsWith("LIMIT_") !== (value !== null)) break;

      this.#position = scanPosition + 1;

      if (word === "UTF" || word === "UTF8") this.#unicode = true;

      options.push({type: "startOption", name: word, value: value});
    }

    return options;
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

  // Parses a \p{name}, \P{name}, \p{^name} or single-letter \pX Unicode
  // property escape, with the position at the p or P.
  #parseUnicodeProperty(letter) {
    this.#position++;

    let negated = letter === "P";

    if (this.#peek() !== "{") {
      if (this.#atEnd()) {
        throw new RegexParseError(
          "malformed \\P or \\p sequence",
          this.#position,
        );
      }

      const name = this.#peek();
      this.#position++;

      if (!GENERAL_CATEGORIES.has(name)) {
        throw new RegexParseError(
          "unknown property after \\P or \\p",
          this.#position,
        );
      }

      return {type: "unicodeProperty", name: name, negated: negated};
    }

    this.#position++;

    if (this.#peek() === "^") {
      negated = !negated;
      this.#position++;
    }

    const nameStart = this.#position;

    while (!this.#atEnd() && this.#peek() !== "}") this.#position++;

    if (this.#atEnd()) {
      throw new RegexParseError(
        "malformed \\P or \\p sequence",
        this.#position,
      );
    }

    const name = this.#source.slice(nameStart, this.#position);
    this.#position++;

    // TODO: validate longer property names (scripts, name=value pairs)
    // against Unicode tables
    if (name === "" || (name.length <= 2 && !GENERAL_CATEGORIES.has(name))) {
      throw new RegexParseError(
        "unknown property after \\P or \\p",
        this.#position,
      );
    }

    return {type: "unicodeProperty", name: name, negated: negated};
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
      if (ALPHA_ASSERTIONS.has(word) && this.#peek() === ":") {
        return this.#parseAlphaAssertion(word, wordStart);
      }

      if (/[a-z]/.test(word)) {
        throw new RegexParseError(
          "(*alpha_assertion) not recognized",
          this.#peek() === ":" ? this.#position : this.#position + 1,
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
  #raiseEscapeError() {
    const char = this.#peek();

    if (UNSUPPORTED_BY_PCRE2_ESCAPES.has(char)) {
      this.#position++;
      throw new RegexParseError(
        "PCRE2 does not support \\F, \\L, \\l, \\N{name}, \\U, or \\u",
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

  #scanOptionLetters() {
    const start = this.#position;

    while (true) {
      const char = this.#peek();

      // ASCII option letters: a alone or the aD, aP, aS, aT, aW pairs
      if (char === "a") {
        this.#position++;
        if ("DPSTW".includes(this.#peek())) this.#position++;
        continue;
      }

      if (char !== undefined && "iJmnsUx".includes(char)) {
        this.#position++;
        continue;
      }

      break;
    }

    return this.#source.slice(start, this.#position);
  }

  // Consumes \Q and \E markers inside a class, toggling the quoting state.
  // \Q inside an active quote is not a marker, because the backslash is
  // literal there.
  #skipClassQuoteMarkers() {
    while (this.#peek() === "\\") {
      const next = this.#source[this.#position + 1];

      if (next === "Q" && !this.#inClassQuote) {
        this.#position += 2;
        this.#inClassQuote = true;
        continue;
      }

      if (next === "E") {
        this.#position += 2;
        this.#inClassQuote = false;
        continue;
      }

      break;
    }
  }

  // Skips a (?#...) comment, with the position at the (.
  #skipComment() {
    this.#position += 3;

    while (!this.#atEnd() && this.#peek() !== ")") this.#position++;

    if (this.#atEnd()) {
      throw new RegexParseError("missing ) after (?# comment", this.#position);
    }

    this.#position++;
  }

  // Skips whitespace and # end-of-line comments in extended mode,
  // outside character classes.
  #skipExtendedWhitespace() {
    while (!this.#atEnd()) {
      const char = this.#peek();

      if (EXTENDED_WHITESPACE.has(char)) {
        this.#position++;
        continue;
      }

      if (char === "#") {
        while (!this.#atEnd() && this.#peek() !== "\n") this.#position++;
        continue;
      }

      break;
    }
  }

  // Scans a {n}, {n,}, {n,m} or {,m} bounds spec. Spaces and tabs around the
  // numbers are allowed, matching PCRE2 behavior.
  // Returns null (without consuming) when the braces don't form a valid spec,
  // in which case { is a literal, matching PCRE2 behavior.
  #tryParseBraceBounds() {
    const source = this.#source;
    let scanPosition = this.#position + 1;

    const skipSpacesAndTabs = () => {
      while (source[scanPosition] === " " || source[scanPosition] === "\t") {
        scanPosition++;
      }
    };

    skipSpacesAndTabs();

    const minStart = scanPosition;
    while (this.#isDigit(source[scanPosition])) scanPosition++;
    const minDigitCount = scanPosition - minStart;

    skipSpacesAndTabs();

    let hasComma = false;
    if (source[scanPosition] === ",") {
      hasComma = true;
      scanPosition++;
      skipSpacesAndTabs();
    }

    const maxStart = scanPosition;
    while (this.#isDigit(source[scanPosition])) scanPosition++;
    const maxDigitCount = scanPosition - maxStart;

    skipSpacesAndTabs();

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

    if (this.#extended) this.#skipExtendedWhitespace();

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

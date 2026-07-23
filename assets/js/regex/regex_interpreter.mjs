"use strict";

import RegexAnalyzer from "./regex_analyzer.mjs";

import {
  codePointInRanges,
  POSIX_SETS,
  SHORTHAND_SETS,
} from "./regex_char_sets.mjs";

// Newline conventions with a two-char CR LF sequence.
const NEWLINE_PAIR_CONVENTIONS = new Set(["any", "anycrlf", "crlf"]);

// Single chars that alone form a complete newline, per convention.
const NEWLINE_SINGLES = {
  any: [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029],
  anycrlf: [0x0a, 0x0d],
  cr: [0x0d],
  crlf: [],
  lf: [0x0a],
  nul: [0x00],
};

// Start-of-pattern verbs that select a newline convention.
const NEWLINE_VERBS = {
  ANY: "any",
  ANYCRLF: "anycrlf",
  CR: "cr",
  CRLF: "crlf",
  LF: "lf",
  NUL: "nul",
};

// Single chars matched by \R, by bsr mode.
const NEWLINE_SEQUENCE_SINGLES = {
  anycrlf: [0x0a, 0x0d],
  unicode: [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029],
};

// Cache of Unicode property name → predicate over a code point.
const propertyMatchers = new Map();

export default class RegexInterpreter {
  // Matches a parsed pattern against a subject string, scanning forward from
  // the start position. Returns {start, end, captures} of the first match,
  // or null. captures[n] holds {start, end} of group n, or null when the
  // group didn't participate (index 0 is unused).
  //
  // Matching uses continuation-passing style: each node matcher calls the
  // continuation with the position after itself, and returning false makes
  // the caller backtrack to its next alternative.
  static match(ast, subject, opts = {}) {
    const groupCount =
      opts.groupCount ?? RegexAnalyzer.buildGroupMap(ast).count;

    const effectiveOpts = $.#mergeStartOptions(ast, opts);
    const startPosition = opts.startPosition ?? 0;

    const state = {
      bsrAnycrlf: effectiveOpts.bsrAnycrlf === true,
      captures: [],
      caseless: effectiveOpts.caseless === true,
      dollarEndonly: effectiveOpts.dollarEndonly === true,
      dotall: effectiveOpts.dotall === true,
      multiline: effectiveOpts.multiline === true,
      newline: effectiveOpts.newline ?? "lf",
      startOffset: startPosition,
      subject: subject,
      ungreedy: effectiveOpts.ungreedy === true,
      unicode: effectiveOpts.unicode === true,
    };

    let start = startPosition;

    while (start <= subject.length) {
      state.captures = [];

      let matchEnd = null;

      const matched = $.#matchNode(ast, state, start, (position) => {
        matchEnd = position;
        return true;
      });

      if (matched) {
        const captures = [null];

        for (let number = 1; number <= groupCount; number++) {
          captures.push(state.captures[number] ?? null);
        }

        return {start: start, end: matchEnd, captures: captures};
      }

      start += start < subject.length ? $.#charLength(state, start) : 1;
    }

    return null;
  }

  // Returns true when a newline sequence ends right before the position,
  // never matching between the CR and LF of a CRLF pair.
  static #afterNewline(state, position) {
    if (position === 0) return false;

    const previous = state.subject.charCodeAt(position - 1);

    if (state.newline === "crlf") {
      return (
        position >= 2 &&
        previous === 0x0a &&
        state.subject.charCodeAt(position - 2) === 0x0d
      );
    }

    if (!NEWLINE_SINGLES[state.newline].includes(previous)) return false;

    // A CR directly followed by LF is the start of a pair, so the position
    // after it is inside the newline
    if (
      previous === 0x0d &&
      NEWLINE_PAIR_CONVENTIONS.has(state.newline) &&
      state.subject.charCodeAt(position) === 0x0a
    ) {
      return false;
    }

    return true;
  }

  // Returns the state updated by an option setting's letters.
  // The x, J, n and ASCII option letters only affect parsing and are already
  // handled by the parser.
  static #applyOptions(state, node) {
    const next = {...state};

    // (?^ resets i, m, n, s and x to their defaults
    if (node.reset) {
      next.caseless = false;
      next.dotall = false;
      next.multiline = false;
    }

    if (node.set.includes("i")) next.caseless = true;
    if (node.set.includes("m")) next.multiline = true;
    if (node.set.includes("s")) next.dotall = true;
    if (node.set.includes("U")) next.ungreedy = true;

    if (node.unset.includes("i")) next.caseless = false;
    if (node.unset.includes("m")) next.multiline = false;
    if (node.unset.includes("s")) next.dotall = false;
    if (node.unset.includes("U")) next.ungreedy = false;

    return next;
  }

  // Returns the case-mapped variants of a code point that differ from it.
  static #caseVariants(codePoint) {
    const char = String.fromCodePoint(codePoint);
    const variants = [];

    for (const mapped of [char.toLowerCase(), char.toUpperCase()]) {
      const mappedCodePoint = mapped.codePointAt(0);

      if (
        mapped.length === String.fromCodePoint(mappedCodePoint).length &&
        mappedCodePoint !== codePoint
      ) {
        variants.push(mappedCodePoint);
      }
    }

    return variants;
  }

  static #charLength(state, position) {
    if (!state.unicode) return 1;

    const codePoint = state.subject.codePointAt(position);

    return codePoint > 0xffff ? 2 : 1;
  }

  static #classItemsMatch(items, codePoint) {
    for (const item of items) {
      switch (item.type) {
        case "literal":
          if (codePoint === item.codePoint) return true;
          break;

        case "posixClass":
          if (
            codePointInRanges(POSIX_SETS[item.name], codePoint) !== item.negated
          ) {
            return true;
          }
          break;

        case "range":
          if (codePoint >= item.from && codePoint <= item.to) return true;
          break;

        case "shorthand":
          if (
            codePointInRanges(SHORTHAND_SETS[item.letter], codePoint) !==
            item.negated
          ) {
            return true;
          }
          break;

        case "unicodeProperty":
          if (
            $.#unicodePropertyMatches(item.name, codePoint) !== item.negated
          ) {
            return true;
          }
          break;

        default:
          throw new Error(
            `unsupported class member for interpretation: ${item.type}`,
          );
      }
    }

    return false;
  }

  static #classMatches(node, codePoint, state) {
    if ($.#classItemsMatch(node.items, codePoint)) return true;

    if (state.caseless) {
      for (const variant of $.#caseVariants(codePoint)) {
        if ($.#classItemsMatch(node.items, variant)) return true;
      }
    }

    return false;
  }

  static #codePointLength(state, codePoint) {
    return state.unicode && codePoint > 0xffff ? 2 : 1;
  }

  static #codePointsEqual(expected, actual, state) {
    if (expected === actual) return true;

    if (!state.caseless) return false;

    return (
      String.fromCodePoint(expected).toLowerCase() ===
      String.fromCodePoint(actual).toLowerCase()
    );
  }

  // Returns true at the subject end, or right before a newline sequence that
  // ends the subject.
  static #endsBeforeFinalNewline(state, position) {
    if (position === state.subject.length) return true;

    const newlineLength = $.#newlineLengthAt(state, position);

    return (
      newlineLength > 0 && position + newlineLength === state.subject.length
    );
  }

  static #isWordCodePoint(codePoint) {
    return (
      (codePoint >= 0x30 && codePoint <= 0x39) ||
      (codePoint >= 0x41 && codePoint <= 0x5a) ||
      codePoint === 0x5f ||
      (codePoint >= 0x61 && codePoint <= 0x7a)
    );
  }

  static #matchAnchor(node, state, position, continuation) {
    let holds;

    switch (node.kind) {
      case "lineStart":
        holds =
          position === 0 ||
          (state.multiline && $.#afterNewline(state, position));
        break;

      case "lineEnd":
        if (state.multiline) {
          holds =
            position === state.subject.length ||
            $.#newlineStartsAt(state, position);
        } else if (state.dollarEndonly) {
          holds = position === state.subject.length;
        } else {
          holds = $.#endsBeforeFinalNewline(state, position);
        }
        break;

      case "matchStart":
        holds = position === state.startOffset;
        break;

      case "nonWordBoundary":
      case "wordBoundary": {
        const beforeIsWord =
          position > 0 &&
          $.#isWordCodePoint(state.subject.charCodeAt(position - 1));

        const atCodePoint = $.#subjectCodePointAt(state, position);
        const atIsWord =
          atCodePoint !== null && $.#isWordCodePoint(atCodePoint);

        holds = (beforeIsWord !== atIsWord) === (node.kind === "wordBoundary");
        break;
      }

      case "subjectEnd":
        holds = position === state.subject.length;
        break;

      case "subjectEndBeforeFinalNewline":
        holds = $.#endsBeforeFinalNewline(state, position);
        break;

      case "subjectStart":
        holds = position === 0;
        break;

      default:
        throw new Error(`unsupported anchor for interpretation: ${node.kind}`);
    }

    return holds && continuation(position);
  }

  // Runs a matcher once and locks its first match in: the match is never
  // backtracked into, and captures set inside are rolled back when the
  // continuation fails. The matcher receives the continuation to call with
  // its end position.
  static #matchAtomically(matcher, state, continuation) {
    const savedCaptures = [...state.captures];
    let lockedPosition = null;

    const found = matcher((endPosition) => {
      lockedPosition = endPosition;
      return true;
    });

    if (!found) return false;

    if (continuation(lockedPosition)) return true;

    state.captures.splice(0, state.captures.length, ...savedCaptures);

    return false;
  }

  static #matchNode(node, state, position, continuation) {
    switch (node.type) {
      case "alternation": {
        let branchState = state;

        for (const branch of node.branches) {
          if ($.#matchNode(branch, branchState, position, continuation)) {
            return true;
          }

          // Option settings leak lexically into subsequent branches,
          // matching PCRE2 behavior
          branchState = $.#stateAfterBranchOptions(branch, branchState);
        }

        return false;
      }

      case "anchor":
        return $.#matchAnchor(node, state, position, continuation);

      case "atomicGroup":
        return $.#matchAtomically(
          (matcherContinuation) =>
            $.#matchNode(node.content, state, position, matcherContinuation),
          state,
          continuation,
        );

      case "class": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if ($.#classMatches(node, codePoint, state) === node.negated) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      case "concatenation":
        return $.#matchSequence(node.items, 0, state, position, continuation);

      case "dot": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if (
          !state.dotall &&
          NEWLINE_SINGLES[state.newline].includes(codePoint)
        ) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      case "group": {
        const previous = state.captures[node.number];

        const matched = $.#matchNode(
          node.content,
          state,
          position,
          (endPosition) => {
            state.captures[node.number] = {start: position, end: endPosition};

            if (continuation(endPosition)) return true;

            state.captures[node.number] = previous;

            return false;
          },
        );

        if (!matched) state.captures[node.number] = previous;

        return matched;
      }

      case "literal": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if (!$.#codePointsEqual(node.codePoint, codePoint, state)) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      // \R matches CRLF as a pair or a single vertical whitespace char,
      // atomically: a matched pair is never given back, matching PCRE2
      // behavior
      case "newlineSequence": {
        if (
          state.subject.charCodeAt(position) === 0x0d &&
          state.subject.charCodeAt(position + 1) === 0x0a
        ) {
          return continuation(position + 2);
        }

        const codePoint = $.#subjectCodePointAt(state, position);
        const singles =
          NEWLINE_SEQUENCE_SINGLES[state.bsrAnycrlf ? "anycrlf" : "unicode"];

        if (codePoint !== null && singles.includes(codePoint)) {
          return continuation(position + 1);
        }

        return false;
      }

      case "nonCapturingGroup":
        return $.#matchNode(node.content, state, position, continuation);

      // \N follows the newline convention like dot, but ignores dotall
      case "notNewline": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if (NEWLINE_SINGLES[state.newline].includes(codePoint)) return false;

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      case "optionGroup":
        return $.#matchNode(
          node.content,
          $.#applyOptions(state, node),
          position,
          continuation,
        );

      case "quantifier":
        return $.#matchQuantifier(node, state, position, continuation);

      case "shorthand": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if (
          codePointInRanges(SHORTHAND_SETS[node.letter], codePoint) ===
          node.negated
        ) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      // TODO: in unicode mode \C should consume one UTF-8 byte instead of
      // one UTF-16 code unit
      case "singleByte":
        if (position >= state.subject.length) return false;

        return continuation(position + 1);

      // Start options are compile metadata and match nothing
      case "startOption":
        return continuation(position);

      case "unicodeProperty": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if ($.#unicodePropertyMatches(node.name, codePoint) === node.negated) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

      default:
        // TODO: shrink as remaining interpreter features are implemented
        throw new Error(
          `unsupported AST node for interpretation: ${node.type}`,
        );
    }
  }

  static #matchQuantifier(node, state, position, continuation) {
    // A possessive quantifier is an atomic group around the greedy quantifier
    if (node.mode === "possessive") {
      return $.#matchAtomically(
        (matcherContinuation) =>
          $.#matchRepetitions(
            node,
            state,
            position,
            0,
            false,
            matcherContinuation,
          ),
        state,
        continuation,
      );
    }

    // The ungreedy option swaps the meaning of greedy and lazy
    const isLazy = (node.mode === "lazy") !== state.ungreedy;

    return $.#matchRepetitions(node, state, position, 0, isLazy, continuation);
  }

  static #matchRepetitions(node, state, position, count, isLazy, continuation) {
    const canStop = count >= node.min;
    const canContinue = node.max === null || count < node.max;

    const tryMore = () =>
      canContinue &&
      $.#matchNode(node.item, state, position, (nextPosition) => {
        // An empty iteration beyond the required minimum would repeat
        // forever, so it stops the repetition, matching PCRE2 behavior
        if (nextPosition === position && count >= node.min) return false;

        return $.#matchRepetitions(
          node,
          state,
          nextPosition,
          count + 1,
          isLazy,
          continuation,
        );
      });

    if (isLazy) {
      if (canStop && continuation(position)) return true;

      return tryMore();
    }

    if (tryMore()) return true;

    return canStop && continuation(position);
  }

  static #matchSequence(items, itemIndex, state, position, continuation) {
    if (itemIndex === items.length) return continuation(position);

    const item = items[itemIndex];

    // An inline option setting applies to the rest of the enclosing group
    if (item.type === "optionSetting") {
      return $.#matchSequence(
        items,
        itemIndex + 1,
        $.#applyOptions(state, item),
        position,
        continuation,
      );
    }

    return $.#matchNode(item, state, position, (nextPosition) =>
      $.#matchSequence(items, itemIndex + 1, state, nextPosition, continuation),
    );
  }

  // Merges start-of-pattern option verbs into the match options.
  static #mergeStartOptions(ast, opts) {
    const effectiveOpts = {...opts};

    if (ast.type !== "concatenation") return effectiveOpts;

    for (const item of ast.items) {
      if (item.type !== "startOption") break;

      if (NEWLINE_VERBS[item.name] !== undefined) {
        effectiveOpts.newline = NEWLINE_VERBS[item.name];
      } else if (item.name === "BSR_ANYCRLF") {
        effectiveOpts.bsrAnycrlf = true;
      } else if (item.name === "BSR_UNICODE") {
        effectiveOpts.bsrAnycrlf = false;
      } else if (item.name === "UTF" || item.name === "UTF8") {
        effectiveOpts.unicode = true;
      }
    }

    return effectiveOpts;
  }

  // Returns the length of the newline sequence starting at the position,
  // or 0 when there is none.
  static #newlineLengthAt(state, position) {
    if (
      NEWLINE_PAIR_CONVENTIONS.has(state.newline) &&
      state.subject.charCodeAt(position) === 0x0d &&
      state.subject.charCodeAt(position + 1) === 0x0a
    ) {
      return 2;
    }

    if (
      NEWLINE_SINGLES[state.newline].includes(
        state.subject.charCodeAt(position),
      )
    ) {
      return 1;
    }

    return 0;
  }

  static #newlineStartsAt(state, position) {
    return $.#newlineLengthAt(state, position) > 0;
  }

  // Returns the state as updated by option settings lexically contained in
  // an alternation branch, at its top concatenation level.
  static #stateAfterBranchOptions(branch, state) {
    if (branch.type === "optionSetting") return $.#applyOptions(state, branch);

    if (branch.type === "concatenation") {
      let currentState = state;

      for (const item of branch.items) {
        currentState = $.#stateAfterBranchOptions(item, currentState);
      }

      return currentState;
    }

    return state;
  }

  static #subjectCodePointAt(state, position) {
    if (position >= state.subject.length) return null;

    return state.unicode
      ? state.subject.codePointAt(position)
      : state.subject.charCodeAt(position);
  }

  // Returns a cached predicate testing a code point against a PCRE2 Unicode
  // property name, built on JS property escapes. Bare non-category names are
  // matched as script extensions, falling back to scripts, following PCRE2.
  static #unicodePropertyMatcher(name) {
    switch (name) {
      case "Any":
        return () => true;

      // Xan matches alphanumeric chars, Xwd additionally the underscore
      case "Xan":
        return (char) => /[\p{L}\p{N}]/u.test(char);

      case "Xwd":
        return (char) => /[\p{L}\p{N}_]/u.test(char);

      // Xps and Xsp both match white space
      case "Xps":
      case "Xsp":
        return (char) => /\p{White_Space}/u.test(char);

      case "Xuc":
        // TODO: implement the universally-named character property
        throw new Error("unsupported Unicode property: Xuc");

      default: {
        const candidates = name.includes("=")
          ? [name]
          : [name, `Script_Extensions=${name}`, `Script=${name}`];

        for (const candidate of candidates) {
          try {
            const regex = new RegExp(`\\p{${candidate}}`, "u");

            return (char) => regex.test(char);
          } catch {
            // Try the next property name form
          }
        }

        throw new Error(`unsupported Unicode property: ${name}`);
      }
    }
  }

  static #unicodePropertyMatches(name, codePoint) {
    if (!propertyMatchers.has(name)) {
      propertyMatchers.set(name, $.#unicodePropertyMatcher(name));
    }

    return propertyMatchers.get(name)(String.fromCodePoint(codePoint));
  }
}

const $ = RegexInterpreter;

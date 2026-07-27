"use strict";

import ERTS from "../../erts.mjs";
import RegexAnalyzer from "./regex_analyzer.mjs";

import {
  codePointInRanges,
  POSIX_SETS,
  SHORTHAND_SETS,
} from "./regex_char_sets.mjs";

import {
  newlineLengthAt,
  NEWLINE_PAIR_CONVENTIONS,
  NEWLINE_SEQUENCE_SINGLES,
  NEWLINE_SINGLES,
  NEWLINE_VERBS,
} from "./regex_newlines.mjs";

// The PCRE2 version emulated by the (?(VERSION condition, matching the
// version Erlang/OTP ships.
const EMULATED_PCRE2_VERSION = {major: 10, minor: 47};

// How far a lookbehind scans back for its content start: parsing limits
// lookbehind branches to 255 chars, each at most 2 UTF-16 units.
const LOOKBEHIND_MAX_UNITS = 510;

// Cache of Unicode property name → predicate over a code point.
const propertyMatchers = new Map();

// Signals thrown by backtracking control verbs. They unwind the normal
// backtracking and are caught at match, subroutine, lookaround or
// alternation boundaries.
class AcceptSignal {
  constructor(position) {
    this.position = position;
  }
}

class CommitSignal {}

// Thrown when a match limit is exceeded; the whole match reports no match,
// matching Erlang behavior.
class LimitSignal {}

class PruneSignal {}

class SkipSignal {
  constructor(position) {
    this.position = position;
  }
}

class ThenSignal {}

export default class RegexInterpreter {
  // Matches a parsed pattern against a subject string, scanning forward from
  // the start position. Returns {start, end, captures} of the first match,
  // or null. captures[n] holds {start, end} of group n, or null when the
  // group didn't participate (index 0 is unused).
  //
  // opts.maxStartPosition bounds the scan: positions past it are not
  // attempted. notbol and noteol make the subject boundaries not count as
  // line boundaries, and notempty/notemptyAtStart reject empty matches
  // (everywhere or at the start position only) during backtracking, so a
  // longer match at the same position can still be found.
  //
  // Matching uses continuation-passing style: each node matcher calls the
  // continuation with the position after itself, and returning false makes
  // the caller backtrack to its next alternative.
  static match(ast, subject, opts = {}) {
    const groupMap = opts.groupMap ?? RegexAnalyzer.buildGroupMap(ast);
    const groupCount = groupMap.count;

    const effectiveOpts = $.#mergeStartOptions(ast, opts);
    const startPosition = opts.startPosition ?? 0;

    const maxStartPosition = Math.min(
      subject.length,
      opts.maxStartPosition ?? Infinity,
    );

    const state = {
      bsrAnycrlf: effectiveOpts.bsr_anycrlf === true,
      callStack: [],
      captures: [],
      caseless: effectiveOpts.caseless === true,
      depth: 0,
      dollarEndonly: effectiveOpts.dollar_endonly === true,
      dotall: effectiveOpts.dotall === true,
      groupNames: groupMap.names,
      marks: [],
      matchLimit: effectiveOpts.matchLimit ?? 10_000_000,
      matchLimitRecursion: effectiveOpts.matchLimitRecursion ?? 10_000_000,
      multiline: effectiveOpts.multiline === true,
      newline: effectiveOpts.newline ?? "lf",
      notbol: opts.notbol === true,
      noteol: opts.noteol === true,
      openGroups: [],
      reportedStart: null,
      startOffset: startPosition,
      steps: 0,
      subject: subject,
      subroutines: $.#buildSubroutineTable(ast),
      ungreedy: effectiveOpts.ungreedy === true,
      unicode: effectiveOpts.unicode === true,
    };

    let start = startPosition;

    while (start <= maxStartPosition) {
      state.captures = [];
      state.marks = [];
      state.openGroups = [];
      state.reportedStart = null;

      // An empty match is one whose reported region has zero length
      const rejectEmpty =
        opts.notempty === true ||
        (opts.notemptyAtStart === true && start === startPosition);

      let matched = false;
      let matchEnd = null;
      let skipTo = null;

      try {
        matched = $.#matchNode(ast, state, start, (position) => {
          if (rejectEmpty && position === (state.reportedStart ?? start)) {
            return false;
          }

          matchEnd = position;
          return true;
        });
      } catch (signal) {
        if (signal instanceof AcceptSignal) {
          if (
            !rejectEmpty ||
            signal.position !== (state.reportedStart ?? start)
          ) {
            matched = true;
            matchEnd = signal.position;
          }
        } else if (signal instanceof CommitSignal) {
          // (*COMMIT) abandons the whole match
          return null;
        } else if (signal instanceof SkipSignal) {
          skipTo = signal.position;
        } else if (
          signal instanceof PruneSignal ||
          signal instanceof ThenSignal
        ) {
          // The attempt at this start position is abandoned
        } else if (signal instanceof LimitSignal) {
          return null;
        } else if (signal instanceof RangeError) {
          // The continuation-passing depth exceeded the JS stack, which is
          // treated as an exceeded match limit
          return null;
        } else {
          throw signal;
        }
      }

      if (matched) {
        const captures = [null];

        for (let number = 1; number <= groupCount; number++) {
          captures.push(state.captures[number] ?? null);
        }

        return {
          start: state.reportedStart ?? start,
          end: matchEnd,
          captures: captures,
        };
      }

      // Anchored matching attempts only the start position
      if (opts.anchored === true) return null;

      if (skipTo !== null && skipTo > start) {
        start = skipTo;
      } else {
        start += start < subject.length ? $.#charLength(state, start) : 1;
      }
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

  // Builds the subroutine call table: group number → group node, with 0
  // mapping to the whole pattern. The first definition wins for numbers
  // repeated in branch reset groups.
  static #buildSubroutineTable(ast) {
    const table = new Map([[0, ast]]);

    $.#collectSubroutines(ast, table);

    return table;
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

  static #collectSubroutines(node, table) {
    switch (node.type) {
      case "alternation":
        for (const branch of node.branches) {
          $.#collectSubroutines(branch, table);
        }
        break;

      case "atomicGroup":
      case "branchResetGroup":
      case "lookaround":
      case "nonCapturingGroup":
      case "optionGroup":
      case "scriptRun":
        $.#collectSubroutines(node.content, table);
        break;

      case "concatenation":
        for (const item of node.items) {
          $.#collectSubroutines(item, table);
        }
        break;

      case "conditional":
        if (node.condition.kind === "assertion") {
          $.#collectSubroutines(node.condition.assertion, table);
        }

        $.#collectSubroutines(node.yes, table);

        if (node.no !== null) $.#collectSubroutines(node.no, table);
        break;

      case "group":
        if (!table.has(node.number)) table.set(node.number, node);

        $.#collectSubroutines(node.content, table);
        break;

      case "quantifier":
        $.#collectSubroutines(node.item, table);
        break;

      default:
        break;
    }
  }

  // Evaluates a conditional's condition at the given position.
  static #conditionHolds(condition, state, position) {
    switch (condition.kind) {
      case "assertion":
        return $.#matchNode(condition.assertion, state, position, () => true);

      // A DEFINE condition is never true, its content is only callable
      case "define":
        return false;

      case "group": {
        const numbers =
          condition.number !== null
            ? [condition.number]
            : (state.groupNames.get(condition.name) ?? []);

        return numbers.some(
          (number) =>
            state.captures[number] !== undefined &&
            state.captures[number] !== null,
        );
      }

      case "recursion": {
        if (condition.number === null && condition.name === null) {
          return state.callStack.length > 0;
        }

        const currentCall = state.callStack.at(-1);

        if (condition.number !== null) {
          return currentCall === condition.number;
        }

        return (state.groupNames.get(condition.name) ?? []).includes(
          currentCall,
        );
      }

      case "version": {
        const {major, minor} = EMULATED_PCRE2_VERSION;

        if (condition.gte) {
          return (
            major > condition.major ||
            (major === condition.major && minor >= condition.minor)
          );
        }

        return major === condition.major && minor === condition.minor;
      }

      default:
        throw new Error(
          `unsupported condition for interpretation: ${condition.kind}`,
        );
    }
  }

  // Returns true at the subject end, or right before a newline sequence that
  // ends the subject.
  static #endsBeforeFinalNewline(state, position) {
    if (position === state.subject.length) return true;

    const newlineLength = newlineLengthAt(
      state.newline,
      state.subject,
      position,
    );

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
          (position === 0 && !state.notbol) ||
          (state.multiline && $.#afterNewline(state, position));
        break;

      case "lineEnd":
        if (state.multiline) {
          holds =
            (position === state.subject.length && !state.noteol) ||
            newlineLengthAt(state.newline, state.subject, position) > 0;
        } else if (state.dollarEndonly) {
          holds = position === state.subject.length && !state.noteol;
        } else {
          holds = !state.noteol && $.#endsBeforeFinalNewline(state, position);
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

  // Matches the text of a capture at the given position, honoring caseless
  // matching. Returns the end position, or null without a match.
  static #matchCapturedText(state, capture, position) {
    let capturePosition = capture.start;
    let subjectPosition = position;

    while (capturePosition < capture.end) {
      const capturedCodePoint = $.#subjectCodePointAt(state, capturePosition);
      const subjectCodePoint = $.#subjectCodePointAt(state, subjectPosition);

      if (subjectCodePoint === null) return null;

      if (!$.#codePointsEqual(capturedCodePoint, subjectCodePoint, state)) {
        return null;
      }

      capturePosition += $.#codePointLength(state, capturedCodePoint);
      subjectPosition += $.#codePointLength(state, subjectCodePoint);
    }

    return subjectPosition;
  }

  // Matches a lookaround assertion. All lookarounds are zero-width: the
  // continuation runs at the original position. Atomic lookarounds lock the
  // first internal match in, non-atomic ones retry internal alternatives
  // when the continuation fails.
  static #matchLookaround(node, state, position, continuation) {
    const assertionMatcher = (innerContinuation) => {
      if (node.direction === "ahead") {
        return $.#matchNode(node.content, state, position, innerContinuation);
      }

      // Lookbehind: the content must match ending exactly at the position
      const lowerBound = Math.max(0, position - LOOKBEHIND_MAX_UNITS);

      for (let from = lowerBound; from <= position; from++) {
        const matched = $.#matchNode(
          node.content,
          state,
          from,
          (endPosition) =>
            endPosition === position && innerContinuation(endPosition),
        );

        if (matched) return true;
      }

      return false;
    };

    // Verb signals act only within the assertion: (*ACCEPT) makes it
    // succeed, the other verbs make it fail
    const runConfined = (matcher) => {
      try {
        return {found: matcher()};
      } catch (signal) {
        if (signal instanceof AcceptSignal)
          return {accepted: true, found: true};

        if (
          signal instanceof CommitSignal ||
          signal instanceof PruneSignal ||
          signal instanceof SkipSignal ||
          signal instanceof ThenSignal
        ) {
          return {found: false};
        }

        throw signal;
      }
    };

    if (node.negated) {
      // A negative assertion retains no captures from its content
      const savedCaptures = [...state.captures];
      const {found} = runConfined(() => assertionMatcher(() => true));

      state.captures.splice(0, state.captures.length, ...savedCaptures);

      return !found && continuation(position);
    }

    if (node.atomic) {
      const savedCaptures = [...state.captures];

      if (!runConfined(() => assertionMatcher(() => true)).found) return false;

      if (continuation(position)) return true;

      state.captures.splice(0, state.captures.length, ...savedCaptures);

      return false;
    }

    const result = runConfined(() =>
      assertionMatcher(() => continuation(position)),
    );

    return result.accepted === true ? continuation(position) : result.found;
  }

  static #matchNode(node, state, position, continuation) {
    if (++state.steps > state.matchLimit) throw new LimitSignal();

    if (state.depth >= state.matchLimitRecursion) throw new LimitSignal();

    state.depth++;

    try {
      return $.#matchNodeDispatch(node, state, position, continuation);
    } finally {
      state.depth--;
    }
  }

  static #matchNodeDispatch(node, state, position, continuation) {
    switch (node.type) {
      case "alternation": {
        let branchState = state;

        for (const branch of node.branches) {
          try {
            if ($.#matchNode(branch, branchState, position, continuation)) {
              return true;
            }
          } catch (signal) {
            // (*THEN) skips to the next branch of the innermost alternation
            if (!(signal instanceof ThenSignal)) throw signal;
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

      case "backreference": {
        const numbers =
          node.number !== null
            ? [node.number]
            : (state.groupNames.get(node.name) ?? []);

        // A reference by a duplicate name uses the first participating group
        for (const number of numbers) {
          const capture = state.captures[number];

          if (capture === undefined || capture === null) continue;

          const endPosition = $.#matchCapturedText(state, capture, position);

          return endPosition === null ? false : continuation(endPosition);
        }

        // A reference to a group that didn't participate fails,
        // unlike in JS, where it matches empty
        return false;
      }

      case "branchResetGroup":
        return $.#matchNode(node.content, state, position, continuation);

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

      case "conditional": {
        const savedCaptures = [...state.captures];
        const branch = $.#conditionHolds(node.condition, state, position)
          ? node.yes
          : node.no;

        const matched =
          branch === null
            ? continuation(position)
            : $.#matchNode(branch, state, position, continuation);

        // Roll back captures set by an assertion condition on failure
        if (!matched) {
          state.captures.splice(0, state.captures.length, ...savedCaptures);
        }

        return matched;
      }

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

      // \X matches one extended grapheme cluster, in byte mode too,
      // where a CRLF pair still forms a single cluster
      case "graphemeCluster": {
        if (position >= state.subject.length) return false;

        if (state.graphemeSegments === undefined) {
          state.graphemeSegments = ERTS.graphemeSegmenter.segment(
            state.subject,
          );
        }

        const segment = state.graphemeSegments.containing(position);

        return continuation(segment.index + segment.segment.length);
      }

      case "group": {
        const previous = state.captures[node.number];

        // Track the open group so (*ACCEPT) can capture it mid-content
        state.openGroups.push({number: node.number, start: position});

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

        state.openGroups.pop();

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

      case "lookaround":
        return $.#matchLookaround(node, state, position, continuation);

      // \K resets the reported match start to the current position
      case "matchStartReset": {
        const savedReportedStart = state.reportedStart;

        state.reportedStart = position;

        if (continuation(position)) return true;

        state.reportedStart = savedReportedStart;

        return false;
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

      case "subroutine": {
        const number = node.number ?? state.groupNames.get(node.name)[0];
        const target = state.subroutines.get(number);
        const savedCaptures = [...state.captures];

        state.callStack.push(number);

        const callContinuation = (endPosition) => {
          // Captures set inside a completed call are restored on exit,
          // and the call is no longer active during the continuation
          const callCaptures = [...state.captures];

          state.captures.splice(0, state.captures.length, ...savedCaptures);
          state.callStack.pop();

          if (continuation(endPosition)) return true;

          // Calls are not atomic: restore the call state to backtrack into it
          state.captures.splice(0, state.captures.length, ...callCaptures);
          state.callStack.push(number);

          return false;
        };

        let matched;

        try {
          matched = $.#matchNode(target, state, position, callContinuation);
        } catch (signal) {
          // Verb signals act only within the call: (*ACCEPT) ends it
          // successfully at its position, the other verbs make it fail
          if (signal instanceof AcceptSignal) {
            matched = callContinuation(signal.position);
          } else if (
            signal instanceof CommitSignal ||
            signal instanceof PruneSignal ||
            signal instanceof SkipSignal ||
            signal instanceof ThenSignal
          ) {
            matched = false;
          } else {
            throw signal;
          }
        }

        if (!matched) state.callStack.pop();

        return matched;
      }

      case "verb":
        return $.#matchVerb(node, state, position, continuation);

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

  // Matches a backtracking control verb. FAIL and MARK act locally, the
  // other verbs throw signals when backtracked into, unwinding to their
  // handling boundary.
  static #matchVerb(node, state, position, continuation) {
    switch (node.verb) {
      case "accept": {
        // Groups still open at this point are captured up to here
        for (const openGroup of state.openGroups) {
          if (
            state.captures[openGroup.number] === undefined ||
            state.captures[openGroup.number] === null
          ) {
            state.captures[openGroup.number] = {
              start: openGroup.start,
              end: position,
            };
          }
        }

        throw new AcceptSignal(position);
      }

      case "commit":
        if (continuation(position)) return true;

        throw new CommitSignal();

      case "fail":
        return false;

      case "mark": {
        state.marks.push({name: node.name, position: position});

        if (continuation(position)) return true;

        state.marks.pop();

        return false;
      }

      case "prune":
        if (continuation(position)) return true;

        throw new PruneSignal();

      case "skip": {
        if (continuation(position)) return true;

        if (node.name !== null) {
          const mark = state.marks.findLast(
            (candidate) => candidate.name === node.name,
          );

          // Without a matching mark, a named (*SKIP) is ignored
          if (mark === undefined) return false;

          throw new SkipSignal(mark.position);
        }

        throw new SkipSignal(position);
      }

      case "then":
        if (continuation(position)) return true;

        throw new ThenSignal();

      default:
        throw new Error(`unsupported verb for interpretation: ${node.verb}`);
    }
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
        effectiveOpts.bsr_anycrlf = true;
      } else if (item.name === "BSR_UNICODE") {
        effectiveOpts.bsr_anycrlf = false;
      } else if (item.name === "LIMIT_DEPTH") {
        // Limit verbs cap the limits, they can't raise them
        effectiveOpts.matchLimitRecursion = Math.min(
          effectiveOpts.matchLimitRecursion ?? Infinity,
          item.value,
        );
      } else if (item.name === "LIMIT_MATCH") {
        effectiveOpts.matchLimit = Math.min(
          effectiveOpts.matchLimit ?? Infinity,
          item.value,
        );
      } else if (item.name === "UTF" || item.name === "UTF8") {
        effectiveOpts.unicode = true;
      }
    }

    return effectiveOpts;
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

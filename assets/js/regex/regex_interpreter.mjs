"use strict";

import RegexAnalyzer from "./regex_analyzer.mjs";

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

    const state = {
      captures: [],
      caseless: opts.caseless === true,
      subject: subject,
      ungreedy: opts.ungreedy === true,
      unicode: opts.unicode === true,
    };

    let start = opts.startPosition ?? 0;

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

        case "range":
          if (codePoint >= item.from && codePoint <= item.to) return true;
          break;

        default:
          // TODO: shrink as remaining interpreter features are implemented
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

      case "nonCapturingGroup":
        return $.#matchNode(node.content, state, position, continuation);

      case "optionGroup":
        return $.#matchNode(
          node.content,
          $.#applyOptions(state, node),
          position,
          continuation,
        );

      case "quantifier":
        return $.#matchQuantifier(node, state, position, continuation);

      // Start options are compile metadata and match nothing
      case "startOption":
        return continuation(position);

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
}

const $ = RegexInterpreter;

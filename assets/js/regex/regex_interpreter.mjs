"use strict";

export default class RegexInterpreter {
  // Matches a parsed pattern against a subject string, scanning forward from
  // the start position. Returns {start, end} of the first match, or null.
  //
  // Matching uses continuation-passing style: each node matcher calls the
  // continuation with the position after itself, and returning false makes
  // the caller backtrack to its next alternative.
  static match(ast, subject, opts = {}) {
    const state = {
      caseless: opts.caseless === true,
      subject: subject,
      ungreedy: opts.ungreedy === true,
      unicode: opts.unicode === true,
    };

    let start = opts.startPosition ?? 0;

    while (start <= subject.length) {
      let matchEnd = null;

      const matched = $.#matchNode(ast, state, start, (position) => {
        matchEnd = position;
        return true;
      });

      if (matched) return {start: start, end: matchEnd};

      start += start < subject.length ? $.#charLength(state, start) : 1;
    }

    return null;
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

  static #matchNode(node, state, position, continuation) {
    switch (node.type) {
      case "alternation":
        for (const branch of node.branches) {
          if ($.#matchNode(branch, state, position, continuation)) {
            return true;
          }
        }

        return false;

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

      case "literal": {
        const codePoint = $.#subjectCodePointAt(state, position);

        if (codePoint === null) return false;

        if (!$.#codePointsEqual(node.codePoint, codePoint, state)) {
          return false;
        }

        return continuation(position + $.#codePointLength(state, codePoint));
      }

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
    if (node.mode === "possessive") {
      // TODO: remove when atomic matching is implemented
      throw new Error(
        "unsupported quantifier mode for interpretation: possessive",
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

    return $.#matchNode(items[itemIndex], state, position, (nextPosition) =>
      $.#matchSequence(items, itemIndex + 1, state, nextPosition, continuation),
    );
  }

  static #subjectCodePointAt(state, position) {
    if (position >= state.subject.length) return null;

    return state.unicode
      ? state.subject.codePointAt(position)
      : state.subject.charCodeAt(position);
  }
}

const $ = RegexInterpreter;

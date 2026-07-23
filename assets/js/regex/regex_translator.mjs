"use strict";

import {POSIX_SETS, SHORTHAND_SETS} from "./regex_char_sets.mjs";

// Chars that must be escaped inside a character class.
const CLASS_METACHARS = new Set([..."\\]^-"]);

// Chars that must be escaped outside character classes.
const METACHARS = new Set([..."$()*+.?[\\]^{|}"]);

// Newline-convention-dependent translations. The dot exclusion sets contain
// only chars that alone form a complete newline, so the crlf set is empty.
// Multiline ^ never matches between the CR and LF of a CRLF pair, while $
// does match there under the anycrlf and any conventions.
const NEWLINE_VARIANTS = {
  any: {
    dot: "[^\\x0a-\\x0d\\u0085\\u2028-\\u2029]",
    endBeforeFinal: "(?=(?:\\r\\n|[\\x0a-\\x0d\\u0085\\u2028-\\u2029])?$)",
    lineEndMultiline: "(?=[\\x0a-\\x0d\\u0085\\u2028-\\u2029]|$)",
    lineStartMultiline:
      "(?:^|(?<=[\\x0a-\\x0c\\u0085\\u2028-\\u2029])|(?<=\\x0d)(?!\\x0a))",
  },
  anycrlf: {
    dot: "[^\\r\\n]",
    endBeforeFinal: "(?=(?:\\r\\n|\\r|\\n)?$)",
    lineEndMultiline: "(?=\\r|\\n|$)",
    lineStartMultiline: "(?:^|(?<=\\n)|(?<=\\r)(?!\\n))",
  },
  cr: {
    dot: "[^\\r]",
    endBeforeFinal: "(?=\\r?$)",
    lineEndMultiline: "(?=\\r|$)",
    lineStartMultiline: "(?:^|(?<=\\r))",
  },
  crlf: {
    dot: "[\\s\\S]",
    endBeforeFinal: "(?=(?:\\r\\n)?$)",
    lineEndMultiline: "(?=\\r\\n|$)",
    lineStartMultiline: "(?:^|(?<=\\r\\n))",
  },
  lf: {
    dot: "[^\\n]",
    endBeforeFinal: "(?=\\n?$)",
    lineEndMultiline: "(?=\\n|$)",
    lineStartMultiline: "(?:^|(?<=\\n))",
  },
  nul: {
    dot: "[^\\x00]",
    endBeforeFinal: "(?=\\x00?$)",
    lineEndMultiline: "(?=\\x00|$)",
    lineStartMultiline: "(?:^|(?<=\\x00))",
  },
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

export default class RegexTranslator {
  // Translates a parsed pattern into JS RegExp source and flags with
  // matching semantics, plus the mapping from PCRE2 group numbers to JS group
  // numbers, which diverge when the translation adds synthetic groups.
  // Only patterns routed to the native engine are translatable.
  static translate(ast, opts = {}) {
    const effectiveOpts = $.#mergeStartOptions(ast, opts);

    const context = {
      bsrAnycrlf: effectiveOpts.bsrAnycrlf === true,
      caseless: effectiveOpts.caseless === true,
      dollarEndonly: effectiveOpts.dollarEndonly === true,
      dotall: effectiveOpts.dotall === true,
      maxCodePoint: effectiveOpts.unicode === true ? 0x10ffff : 0xff,
      multiline: effectiveOpts.multiline === true,
      newline: effectiveOpts.newline ?? "lf",
      // Group numbering state, shared across derived contexts
      state: {groupMapping: new Map(), jsGroupCount: 0},
      ungreedy: effectiveOpts.ungreedy === true,
      unicode: effectiveOpts.unicode === true,
    };

    let flags = "";

    if (effectiveOpts.caseless === true) flags += "i";
    if (effectiveOpts.unicode === true) flags += "u";

    return {
      source: $.#translateNode(ast, context),
      flags: flags,
      groupMapping: context.state.groupMapping,
    };
  }

  // Returns the context updated by an option setting's letters.
  // The x, J, n and ASCII option letters only affect parsing and are already
  // handled by the parser.
  static #applyOptions(context, node) {
    const next = {...context};

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

  // Returns the ranges of all code points up to maxCodePoint that are not
  // covered by the given sorted ranges.
  static #complementRanges(ranges, maxCodePoint) {
    const complement = [];
    let nextCodePoint = 0;

    for (const [from, to] of ranges) {
      if (from > nextCodePoint) complement.push([nextCodePoint, from - 1]);
      nextCodePoint = to + 1;
    }

    if (nextCodePoint <= maxCodePoint) {
      complement.push([nextCodePoint, maxCodePoint]);
    }

    return complement;
  }

  static #escapeChar(codePoint) {
    const char = String.fromCodePoint(codePoint);

    if (METACHARS.has(char)) return `\\${char}`;

    return $.#escapeCharCommon(codePoint, char);
  }

  static #escapeCharCommon(codePoint, char) {
    if (codePoint < 32 || codePoint === 127) {
      return `\\x${codePoint.toString(16).padStart(2, "0")}`;
    }

    if (codePoint > 0xffff) return `\\u{${codePoint.toString(16)}}`;

    return char;
  }

  static #escapeClassChar(codePoint) {
    const char = String.fromCodePoint(codePoint);

    if (CLASS_METACHARS.has(char)) return `\\${char}`;

    return $.#escapeCharCommon(codePoint, char);
  }

  // Merges start-of-pattern option verbs into the compile options.
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

  static #quantifierBounds(node) {
    if (node.min === 0 && node.max === null) return "*";
    if (node.min === 1 && node.max === null) return "+";
    if (node.min === 0 && node.max === 1) return "?";
    if (node.max === null) return `{${node.min},}`;
    if (node.min === node.max) return `{${node.min}}`;

    return `{${node.min},${node.max}}`;
  }

  static #rangesToClassContent(ranges) {
    return ranges
      .map(([from, to]) =>
        from === to
          ? $.#escapeClassChar(from)
          : `${$.#escapeClassChar(from)}-${$.#escapeClassChar(to)}`,
      )
      .join("");
  }

  // Emits a set as class content, complementing it for negated set members,
  // because JS classes can't nest negation.
  static #setToClassContent(ranges, negated, context) {
    const effectiveRanges = negated
      ? $.#complementRanges(ranges, context.maxCodePoint)
      : ranges;

    return $.#rangesToClassContent(effectiveRanges);
  }

  static #translateAnchor(node, context) {
    const variant = NEWLINE_VARIANTS[context.newline];

    switch (node.kind) {
      // PCRE2 multiline ^ recognizes only the configured newline convention,
      // while the JS m-flag ^ has its own line terminator set, so multiline
      // is always handled by rewriting instead of the m flag
      case "lineStart":
        return context.multiline ? variant.lineStartMultiline : "^";

      // Without dollar_endonly, $ also matches before a final newline
      case "lineEnd":
        if (context.multiline) return variant.lineEndMultiline;

        return context.dollarEndonly ? "$" : variant.endBeforeFinal;

      case "nonWordBoundary":
        return "\\B";

      case "subjectEnd":
        return "$";

      case "subjectEndBeforeFinalNewline":
        return variant.endBeforeFinal;

      case "subjectStart":
        return "^";

      case "wordBoundary":
        return "\\b";

      default:
        throw new Error(
          `unsupported anchor for native translation: ${node.kind}`,
        );
    }
  }

  static #translateClass(node, context) {
    let members = "";

    for (const item of node.items) {
      switch (item.type) {
        case "literal":
          members += $.#escapeClassChar(item.codePoint);
          break;

        case "posixClass":
          members += $.#setToClassContent(
            POSIX_SETS[item.name],
            item.negated,
            context,
          );
          break;

        case "range":
          members += `${$.#escapeClassChar(item.from)}-${$.#escapeClassChar(item.to)}`;
          break;

        case "shorthand":
          members += $.#setToClassContent(
            SHORTHAND_SETS[item.letter],
            item.negated,
            context,
          );
          break;

        default:
          // TODO: shrink as remaining translator rewrites are implemented
          throw new Error(
            `unsupported class member for native translation: ${item.type}`,
          );
      }
    }

    return `[${node.negated ? "^" : ""}${members}]`;
  }

  static #translateNode(node, context) {
    switch (node.type) {
      case "alternation":
        return node.branches
          .map((branch) => $.#translateNode(branch, context))
          .join("|");

      case "anchor":
        return $.#translateAnchor(node, context);

      // Atomic groups are emulated with a capturing lookahead plus a
      // backreference: JS lookaheads are atomic, and the backreference locks
      // in the captured text
      case "atomicGroup": {
        const jsNumber = ++context.state.jsGroupCount;
        const content = $.#translateNode(node.content, context);

        return `(?=(${content}))\\${jsNumber}`;
      }

      case "backreference":
        // Native routing guarantees backreferences point to already emitted
        // groups, so the renumbering is always known here
        return node.number !== null
          ? `\\${context.state.groupMapping.get(node.number)}`
          : `\\k<${node.name}>`;

      case "class":
        return $.#translateClass(node, context);

      case "concatenation": {
        let result = "";
        let currentContext = context;

        for (let index = 0; index < node.items.length; index++) {
          const item = node.items[index];

          // An inline option setting applies to the rest of the enclosing
          // group, so the remaining items are translated with the updated
          // context, in a caseless modifier group when the i option changed
          if (item.type === "optionSetting") {
            const nextContext = $.#applyOptions(currentContext, item);
            const rest = {
              type: "concatenation",
              items: node.items.slice(index + 1),
            };
            const restSource = $.#translateNode(rest, nextContext);

            if (nextContext.caseless !== currentContext.caseless) {
              return `${result}(?${nextContext.caseless ? "i" : "-i"}:${restSource})`;
            }

            return result + restSource;
          }

          result +=
            item.type === "alternation"
              ? `(?:${$.#translateNode(item, currentContext)})`
              : $.#translateNode(item, currentContext);
        }

        return result;
      }

      // PCRE2 dot exclusions follow the newline convention, while JS dot has
      // its own line terminator set, so dot is always translated to an
      // explicit class
      case "dot":
        return context.dotall
          ? "[\\s\\S]"
          : NEWLINE_VARIANTS[context.newline].dot;

      case "group": {
        const jsNumber = ++context.state.jsGroupCount;

        context.state.groupMapping.set(node.number, jsNumber);

        const content = $.#translateNode(node.content, context);

        return node.name !== null
          ? `(?<${node.name}>${content})`
          : `(${content})`;
      }

      case "literal":
        return $.#escapeChar(node.codePoint);

      case "lookaround": {
        const content = $.#translateNode(node.content, context);
        const negation = node.negated ? "!" : "=";

        return node.direction === "ahead"
          ? `(?${negation}${content})`
          : `(?<${negation}${content})`;
      }

      // \R matches CRLF as a pair or a single vertical whitespace char,
      // restricted to CR and LF with the bsr_anycrlf option
      case "newlineSequence":
        return context.bsrAnycrlf
          ? "(?:\\r\\n|[\\r\\n])"
          : `(?:\\r\\n|[${$.#rangesToClassContent(SHORTHAND_SETS.v)}])`;

      case "nonCapturingGroup":
        return `(?:${$.#translateNode(node.content, context)})`;

      // \N follows the newline convention like dot, but ignores dotall
      case "notNewline":
        return NEWLINE_VARIANTS[context.newline].dot;

      case "optionGroup": {
        const nextContext = $.#applyOptions(context, node);
        const content = $.#translateNode(node.content, nextContext);

        // Only caseless needs JS-level support (a modifier group), the other
        // options are handled by context-sensitive rewrites
        if (nextContext.caseless !== context.caseless) {
          return `(?${nextContext.caseless ? "i" : "-i"}:${content})`;
        }

        return `(?:${content})`;
      }

      // A standalone option setting has nothing left in its scope
      case "optionSetting":
        return "";

      case "quantifier":
        return $.#translateQuantifier(node, context);

      case "shorthand": {
        // \d and \w match their JS counterparts exactly
        if (node.letter === "d" || node.letter === "w") {
          const escape = node.negated ? node.letter.toUpperCase() : node.letter;

          return `\\${escape}`;
        }

        const content = $.#rangesToClassContent(SHORTHAND_SETS[node.letter]);

        return node.negated ? `[^${content}]` : `[${content}]`;
      }

      // Start options are compile metadata and match nothing
      case "startOption":
        return "";

      default:
        // TODO: shrink as remaining translator rewrites are implemented
        throw new Error(
          `unsupported AST node for native translation: ${node.type}`,
        );
    }
  }

  static #translateQuantifier(node, context) {
    // A possessive quantifier is an atomic group around the greedy
    // quantifier, emulated with the capturing lookahead trick
    if (node.mode === "possessive") {
      const jsNumber = ++context.state.jsGroupCount;
      const itemSource = $.#translateNode(node.item, context);

      return `(?=(${itemSource}${$.#quantifierBounds(node)}))\\${jsNumber}`;
    }

    const itemSource = $.#translateNode(node.item, context);

    // The ungreedy option swaps the meaning of greedy and lazy
    const isLazy = (node.mode === "lazy") !== context.ungreedy;

    return `${itemSource}${$.#quantifierBounds(node)}${isLazy ? "?" : ""}`;
  }
}

const $ = RegexTranslator;

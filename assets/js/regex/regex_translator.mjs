"use strict";

// Chars that must be escaped inside a character class.
const CLASS_METACHARS = new Set([..."\\]^-"]);

// Chars that must be escaped outside character classes.
const METACHARS = new Set([..."$()*+.?[\\]^{|}"]);

// PCRE2 character sets of the POSIX classes, as sorted code point ranges.
const POSIX_SETS = {
  alnum: [
    [0x30, 0x39],
    [0x41, 0x5a],
    [0x61, 0x7a],
  ],
  alpha: [
    [0x41, 0x5a],
    [0x61, 0x7a],
  ],
  ascii: [[0x00, 0x7f]],
  blank: [
    [0x09, 0x09],
    [0x20, 0x20],
  ],
  cntrl: [
    [0x00, 0x1f],
    [0x7f, 0x7f],
  ],
  digit: [[0x30, 0x39]],
  graph: [[0x21, 0x7e]],
  lower: [[0x61, 0x7a]],
  print: [[0x20, 0x7e]],
  punct: [
    [0x21, 0x2f],
    [0x3a, 0x40],
    [0x5b, 0x60],
    [0x7b, 0x7e],
  ],
  space: [
    [0x09, 0x0d],
    [0x20, 0x20],
  ],
  upper: [[0x41, 0x5a]],
  word: [
    [0x30, 0x39],
    [0x41, 0x5a],
    [0x5f, 0x5f],
    [0x61, 0x7a],
  ],
  xdigit: [
    [0x30, 0x39],
    [0x41, 0x46],
    [0x61, 0x66],
  ],
};

// PCRE2 character sets of the shorthand class escapes, as sorted code point
// ranges. The d and w sets match the JS \d and \w escapes exactly, the others
// differ from their JS counterparts.
const SHORTHAND_SETS = {
  d: [[0x30, 0x39]],
  h: [
    [0x09, 0x09],
    [0x20, 0x20],
    [0xa0, 0xa0],
    [0x1680, 0x1680],
    [0x180e, 0x180e],
    [0x2000, 0x200a],
    [0x202f, 0x202f],
    [0x205f, 0x205f],
    [0x3000, 0x3000],
  ],
  s: [
    [0x09, 0x0d],
    [0x20, 0x20],
  ],
  v: [
    [0x0a, 0x0d],
    [0x85, 0x85],
    [0x2028, 0x2029],
  ],
  w: [
    [0x30, 0x39],
    [0x41, 0x5a],
    [0x5f, 0x5f],
    [0x61, 0x7a],
  ],
};

export default class RegexTranslator {
  // Translates a parsed pattern into JS RegExp source and flags with
  // matching semantics. Only patterns routed to the native engine are
  // translatable.
  static translate(ast, opts = {}) {
    const context = {
      caseless: opts.caseless === true,
      dollarEndonly: opts.dollarEndonly === true,
      dotall: opts.dotall === true,
      maxCodePoint: opts.unicode === true ? 0x10ffff : 0xff,
      multiline: opts.multiline === true,
      ungreedy: opts.ungreedy === true,
      unicode: opts.unicode === true,
    };

    let flags = "";

    if (opts.caseless === true) flags += "i";
    if (opts.unicode === true) flags += "u";

    return {source: $.#translateNode(ast, context), flags: flags};
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
    switch (node.kind) {
      // PCRE2 multiline ^ matches only after \n, while the JS m-flag ^ also
      // matches after \r and the line separators, so multiline is always
      // handled by rewriting instead of the m flag
      case "lineStart":
        return context.multiline ? "(?:^|(?<=\\n))" : "^";

      // Without dollar_endonly, $ also matches before a final newline
      case "lineEnd":
        if (context.multiline) return "(?=\\n|$)";

        return context.dollarEndonly ? "$" : "(?=\\n?$)";

      case "nonWordBoundary":
        return "\\B";

      case "subjectEnd":
        return "$";

      case "subjectEndBeforeFinalNewline":
        return "(?=\\n?$)";

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

      case "backreference":
        return node.number !== null ? `\\${node.number}` : `\\k<${node.name}>`;

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

      // PCRE2 dot excludes only \n, while JS dot also excludes \r and the
      // U+2028 and U+2029 line separators, so dot is always translated to an
      // explicit class
      case "dot":
        return context.dotall ? "[\\s\\S]" : "[^\\n]";

      case "group": {
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

      // \R matches CRLF as a pair or a single vertical whitespace char
      case "newlineSequence":
        return `(?:\\r\\n|[${$.#rangesToClassContent(SHORTHAND_SETS.v)}])`;

      case "nonCapturingGroup":
        return `(?:${$.#translateNode(node.content, context)})`;

      // \N always excludes only the newline, regardless of dotall
      case "notNewline":
        return "[^\\n]";

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
    const itemSource = $.#translateNode(node.item, context);
    let bounds;

    if (node.min === 0 && node.max === null) bounds = "*";
    else if (node.min === 1 && node.max === null) bounds = "+";
    else if (node.min === 0 && node.max === 1) bounds = "?";
    else if (node.max === null) bounds = `{${node.min},}`;
    else if (node.min === node.max) bounds = `{${node.min}}`;
    else bounds = `{${node.min},${node.max}}`;

    if (node.mode === "possessive") {
      // TODO: remove when the possessive lookahead-capture rewrite is implemented
      throw new Error(
        "unsupported quantifier mode for native translation: possessive",
      );
    }

    // The ungreedy option swaps the meaning of greedy and lazy
    const isLazy = (node.mode === "lazy") !== context.ungreedy;

    return `${itemSource}${bounds}${isLazy ? "?" : ""}`;
  }
}

const $ = RegexTranslator;

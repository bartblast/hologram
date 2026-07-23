"use strict";

// Chars that must be escaped inside a character class.
const CLASS_METACHARS = new Set([..."\\]^-"]);

// Chars that must be escaped outside character classes.
const METACHARS = new Set([..."$()*+.?[\\]^{|}"]);

export default class RegexTranslator {
  // Translates a parsed pattern into JS RegExp source and flags with
  // matching semantics. Only patterns routed to the native engine are
  // translatable.
  static translate(ast, opts = {}) {
    const context = {
      dotall: opts.dotall === true,
      unicode: opts.unicode === true,
    };

    let flags = "";

    if (opts.caseless === true) flags += "i";
    if (opts.unicode === true) flags += "u";

    return {source: $.#translateNode(ast, context), flags: flags};
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

  static #translateClass(node, context) {
    let members = "";

    for (const item of node.items) {
      switch (item.type) {
        case "literal":
          members += $.#escapeClassChar(item.codePoint);
          break;

        case "range":
          members += `${$.#escapeClassChar(item.from)}-${$.#escapeClassChar(item.to)}`;
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

      case "backreference":
        return node.number !== null ? `\\${node.number}` : `\\k<${node.name}>`;

      case "class":
        return $.#translateClass(node, context);

      case "concatenation":
        return node.items
          .map((item) =>
            item.type === "alternation"
              ? `(?:${$.#translateNode(item, context)})`
              : $.#translateNode(item, context),
          )
          .join("");

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

      case "nonCapturingGroup":
        return `(?:${$.#translateNode(node.content, context)})`;

      case "quantifier":
        return $.#translateQuantifier(node, context);

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

    return `${itemSource}${bounds}${node.mode === "lazy" ? "?" : ""}`;
  }
}

const $ = RegexTranslator;

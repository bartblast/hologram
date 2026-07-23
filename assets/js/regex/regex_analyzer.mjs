"use strict";

export default class RegexAnalyzer {
  // Builds the capture group map for a parsed pattern: the total group count
  // and the mapping from group names to sorted, unique group numbers.
  // A name can map to multiple numbers with the dupnames option, and multiple
  // names can share a number in branch reset groups.
  static buildGroupMap(ast) {
    const groupMap = {count: 0, names: new Map()};

    $.#collectGroups(ast, groupMap);

    for (const [name, numbers] of groupMap.names) {
      groupMap.names.set(
        name,
        [...new Set(numbers)].sort((number1, number2) => number1 - number2),
      );
    }

    return groupMap;
  }

  // Decides which engine matches a parsed pattern: "native" when every
  // construct translates to a JS RegExp with identical semantics (directly or
  // via rewriting), "interpreted" otherwise.
  static route(ast, groupMap, opts = {}) {
    // JS RegExp can't express one name mapping to multiple group numbers
    for (const numbers of groupMap.names.values()) {
      if (numbers.length > 1) return "interpreted";
    }

    const unicode = opts.unicode === true || $.#hasUtfStartOption(ast);

    if ($.#requiresInterpreter(ast, unicode)) return "interpreted";

    // A backreference that can be reached with its group unset matches
    // differently in JS (empty match) than in PCRE2 (failure)
    if ($.#hasUnsafeBackreference(ast, groupMap)) return "interpreted";

    return "native";
  }

  // Returns the set of group numbers that have definitely participated after
  // the node matches, flagging backreferences that can be reached with their
  // group unset.
  static #collectDefiniteGroups(node, definite, groupMap, state) {
    switch (node.type) {
      case "alternation": {
        const branchSets = node.branches.map((branch) =>
          $.#collectDefiniteGroups(branch, new Set(definite), groupMap, state),
        );

        // Only groups definite in every branch stay definite
        let result = branchSets[0];

        for (const branchSet of branchSets.slice(1)) {
          result = new Set([...result].filter((n) => branchSet.has(n)));
        }

        return result;
      }

      case "atomicGroup":
      case "nonCapturingGroup":
      case "optionGroup":
      case "scriptRun":
        return $.#collectDefiniteGroups(
          node.content,
          definite,
          groupMap,
          state,
        );

      case "backreference": {
        const numbers =
          node.number !== null
            ? [node.number]
            : (groupMap.names.get(node.name) ?? []);

        if (!numbers.every((n) => definite.has(n))) state.unsafe = true;

        return definite;
      }

      case "concatenation": {
        let current = definite;

        for (const item of node.items) {
          current = $.#collectDefiniteGroups(item, current, groupMap, state);
        }

        return current;
      }

      case "group": {
        const after = $.#collectDefiniteGroups(
          node.content,
          definite,
          groupMap,
          state,
        );

        after.add(node.number);

        return after;
      }

      case "lookaround": {
        const inner = $.#collectDefiniteGroups(
          node.content,
          new Set(definite),
          groupMap,
          state,
        );

        return node.negated ? definite : inner;
      }

      case "quantifier": {
        const inner = $.#collectDefiniteGroups(
          node.item,
          new Set(definite),
          groupMap,
          state,
        );

        return node.min >= 1 ? inner : definite;
      }

      default:
        return definite;
    }
  }

  static #collectGroups(node, groupMap) {
    switch (node.type) {
      case "alternation":
        for (const branch of node.branches) {
          $.#collectGroups(branch, groupMap);
        }
        break;

      case "atomicGroup":
      case "branchResetGroup":
      case "lookaround":
      case "nonCapturingGroup":
      case "optionGroup":
      case "scriptRun":
        $.#collectGroups(node.content, groupMap);
        break;

      case "concatenation":
        for (const item of node.items) {
          $.#collectGroups(item, groupMap);
        }
        break;

      case "conditional":
        if (node.condition.kind === "assertion") {
          $.#collectGroups(node.condition.assertion, groupMap);
        }

        $.#collectGroups(node.yes, groupMap);

        if (node.no !== null) $.#collectGroups(node.no, groupMap);
        break;

      case "group":
        if (node.number > groupMap.count) groupMap.count = node.number;

        if (node.name !== null) {
          if (!groupMap.names.has(node.name)) {
            groupMap.names.set(node.name, []);
          }

          groupMap.names.get(node.name).push(node.number);
        }

        $.#collectGroups(node.content, groupMap);
        break;

      case "quantifier":
        $.#collectGroups(node.item, groupMap);
        break;

      default:
        break;
    }
  }

  static #hasUnsafeBackreference(ast, groupMap) {
    const state = {unsafe: false};

    $.#collectDefiniteGroups(ast, new Set(), groupMap, state);

    return state.unsafe;
  }

  static #hasUtfStartOption(ast) {
    if (ast.type !== "concatenation") return false;

    for (const item of ast.items) {
      if (item.type !== "startOption") break;

      if (item.name === "UTF" || item.name === "UTF8") return true;
    }

    return false;
  }

  static #requiresInterpreter(node, unicode) {
    switch (node.type) {
      case "anchor":
        return node.kind === "matchStart";

      case "alternation":
        return node.branches.some((branch) =>
          $.#requiresInterpreter(branch, unicode),
        );

      case "atomicGroup":
      case "group":
      case "nonCapturingGroup":
      case "optionGroup":
        return $.#requiresInterpreter(node.content, unicode);

      case "branchResetGroup":
      case "conditional":
      case "graphemeCluster":
      case "matchStartReset":
      case "scriptRun":
      case "singleByte":
      case "subroutine":
      case "verb":
        return true;

      case "class":
        // Property escapes need the JS u flag, unavailable on the byte-mode
        // native path
        return (
          !unicode && node.items.some((item) => item.type === "unicodeProperty")
        );

      case "concatenation":
        return node.items.some((item) => $.#requiresInterpreter(item, unicode));

      case "lookaround":
        return !node.atomic || $.#requiresInterpreter(node.content, unicode);

      case "quantifier":
        return $.#requiresInterpreter(node.item, unicode);

      case "startOption":
        // Match limits require step counting, which only the interpreter does
        return node.name.startsWith("LIMIT_");

      case "unicodeProperty":
        return !unicode;

      default:
        return false;
    }
  }
}

const $ = RegexAnalyzer;

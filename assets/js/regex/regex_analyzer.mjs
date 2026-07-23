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
}

const $ = RegexAnalyzer;

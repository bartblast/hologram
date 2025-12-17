"use strict";

export default class NodeTable {
  static CLIENT_NODE = "hologram_client";

  // Made public to make tests easier
  static data = new Map();

  // Reverse lookup: localIncarnationId -> {node, creation}
  // Made public to make tests easier
  static reverseData = new Map();

  // Made public to make tests easier
  static sequence = 0;

  // Returns 0 for client node, auto-incremented ID for server nodes.
  static getLocalIncarnationId(node, creation) {
    if (node === $.CLIENT_NODE) {
      return 0;
    }

    const key = `${node}:${creation}`;

    if (!$.data.has(key)) {
      $.sequence += 1;
      $.data.set(key, $.sequence);
      $.reverseData.set($.sequence, {node, creation});
    }

    return $.data.get(key);
  }

  static getNodeAndCreation(localIncarnationId) {
    if (localIncarnationId === 0) {
      return {node: $.CLIENT_NODE, creation: 0};
    }

    return $.reverseData.get(localIncarnationId) || null;
  }

  static reset() {
    $.data = new Map();
    $.reverseData = new Map();
    $.sequence = 0;
  }
}

const $ = NodeTable;

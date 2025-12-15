"use strict";

export default class NodeTable {
  static CLIENT_NODE = "hologram_client";

  // Made public to make tests easier
  static data = new Map();

  // Made public to make tests easier
  static sequence = 0;

  // Returns 0 for client node, auto-incremented ID for server nodes.
  static getLocalIncarnationId(nodeName, creation) {
    if (nodeName === $.CLIENT_NODE) {
      return 0;
    }

    const key = `${nodeName}:${creation}`;

    if (!$.data.has(key)) {
      $.sequence += 1;
      $.data.set(key, $.sequence);
    }

    return $.data.get(key);
  }
}

const $ = NodeTable;

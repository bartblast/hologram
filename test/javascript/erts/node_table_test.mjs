"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import NodeTable from "../../../assets/js/erts/node_table.mjs";

defineGlobalErlangAndElixirModules();

describe("NodeTable", () => {
  beforeEach(() => {
    NodeTable.data.clear();
    NodeTable.sequence = 0;
  });

  describe("getLocalIncarnationId()", () => {
    it("returns 0 for client node", () => {
      const result = NodeTable.getLocalIncarnationId("hologram_client", 1);
      assert.equal(result, 0);
    });

    it("returns auto-incremented ID for server nodes", () => {
      const result1 = NodeTable.getLocalIncarnationId("server1", 0);
      const result2 = NodeTable.getLocalIncarnationId("server2", 0);

      assert.equal(result1, 1);
      assert.equal(result2, 2);
    });

    it("returns the same ID for the same node name and creation number", () => {
      const result1 = NodeTable.getLocalIncarnationId("server1", 2);
      const result2 = NodeTable.getLocalIncarnationId("server1", 2);

      assert.equal(result1, 1);
      assert.equal(result2, 1);
    });

    it("returns different IDs for the same node name but different creation number", () => {
      const result1 = NodeTable.getLocalIncarnationId("server1", 3);
      const result2 = NodeTable.getLocalIncarnationId("server1", 4);

      assert.equal(result1, 1);
      assert.equal(result2, 2);
    });
  });

  describe("reset()", () => {
    it("clears the data and resets the sequence", () => {
      // Populate the NodeTable with some data
      NodeTable.getLocalIncarnationId("server1", 1);
      NodeTable.getLocalIncarnationId("server2", 2);

      // Verify data was added
      assert.equal(NodeTable.data.size, 2);
      assert.equal(NodeTable.sequence, 2);

      NodeTable.reset();

      assert.equal(NodeTable.data.size, 0);
      assert.equal(NodeTable.sequence, 0);
    });
  });
});

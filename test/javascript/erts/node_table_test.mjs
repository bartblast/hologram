"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import NodeTable from "../../../assets/js/erts/node_table.mjs";

defineGlobalErlangAndElixirModules();

describe("NodeTable", () => {
  beforeEach(() => {
    NodeTable.reset();
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

  describe("getNodeAndCreation()", () => {
    it("returns node and creation number for client node (localIncarnationId 0)", () => {
      const result = NodeTable.getNodeAndCreation(0);

      assert.deepEqual(result, {node: NodeTable.CLIENT_NODE, creation: 0});
    });

    it("returns node and creation number for server node", () => {
      NodeTable.getLocalIncarnationId("server1", 5);
      const localIncarnationId = NodeTable.getLocalIncarnationId("server2", 6);

      const result = NodeTable.getNodeAndCreation(localIncarnationId);

      assert.deepEqual(result, {node: "server2", creation: 6});
    });

    it("returns null for non-existent localIncarnationId", () => {
      const result = NodeTable.getNodeAndCreation(999);

      assert.equal(result, null);
    });
  });

  describe("reset()", () => {
    it("clears the data and resets the sequence", () => {
      // Populate the NodeTable with some data
      NodeTable.getLocalIncarnationId("server1", 1);
      NodeTable.getLocalIncarnationId("server2", 2);

      // Verify data was added
      assert.equal(NodeTable.data.size, 2);
      assert.equal(NodeTable.reverseData.size, 3);
      assert.equal(NodeTable.sequence, 2);

      NodeTable.reset();

      assert.equal(NodeTable.data.size, 0);
      assert.equal(NodeTable.reverseData.size, 1);
      assert.equal(NodeTable.sequence, 0);
    });
  });
});

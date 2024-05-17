"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import CommandQueue from "../../assets/js/command_queue.mjs";

describe("CommandQueue", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("getNextPending()", () => {
    it("empty queue", () => {
      CommandQueue.items = {};
      assert.isNull(CommandQueue.getNextPending());
    });

    it("non-empty queue", () => {
      const itemA = {
        id: "a",
        command: "dummy_command_a",
        status: "sent",
      };

      const itemC = {
        id: "c",
        command: "dummy_command_c",
        status: "pending",
      };

      const itemB = {
        id: "b",
        command: "dummy_command_b",
        status: "pending",
      };

      CommandQueue.items = {};
      CommandQueue.items["a"] = itemA;
      CommandQueue.items["c"] = itemC;
      CommandQueue.items["b"] = itemB;

      assert.equal(CommandQueue.getNextPending(), itemC);
    });
  });

  it("push()", () => {
    CommandQueue.items = {};

    CommandQueue.push("dummy_command");

    const id = Object.keys(CommandQueue.items)[0];
    assert.match(
      id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );

    const expectedItems = {};
    expectedItems[id] = {
      id: id,
      command: "dummy_command",
      status: "pending",
    };

    assert.deepStrictEqual(CommandQueue.items, expectedItems);
  });

  it("remove()", () => {
    CommandQueue.items = {
      id1: "dummy_item_1",
      id2: "dummy_item_2",
      id3: "dummy_item_3",
    };

    CommandQueue.remove("id2");

    assert.deepStrictEqual(CommandQueue.items, {
      id1: "dummy_item_1",
      id3: "dummy_item_3",
    });
  });
});

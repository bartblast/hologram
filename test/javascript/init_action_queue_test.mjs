"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import InitActionQueue from "../../assets/js/init_action_queue.mjs";

defineGlobalErlangAndElixirModules();

describe("InitActionQueue", () => {
  beforeEach(() => {
    InitActionQueue.queue = [];
  });

  describe("dequeueAll()", () => {
    it("returns empty array when queue is empty", () => {
      const result = InitActionQueue.dequeueAll();

      assert.deepStrictEqual(result, []);
      assert.deepStrictEqual(InitActionQueue.queue, []);
    });

    it("returns all actions and clears queue", () => {
      const action1 = "action_1";
      const action2 = "action_2";
      const action3 = "action_3";

      InitActionQueue.queue = [action1, action2, action3];

      const result = InitActionQueue.dequeueAll();

      assert.deepStrictEqual(result, [action1, action2, action3]);
      assert.deepStrictEqual(InitActionQueue.queue, []);
    });

    it("returns copy of actions array", () => {
      InitActionQueue.queue = ["action"];

      const result = InitActionQueue.dequeueAll();
      result.push("modified");

      // Original queue should remain empty after dequeueAll
      assert.deepStrictEqual(InitActionQueue.queue, []);
    });
  });

  describe("enqueue()", () => {
    it("adds action to queue", () => {
      const action1 = "action_1";
      const action2 = "action_2";

      InitActionQueue.enqueue(action1);
      InitActionQueue.enqueue(action2);

      assert.deepStrictEqual(InitActionQueue.queue, [action1, action2]);
    });
  });
});

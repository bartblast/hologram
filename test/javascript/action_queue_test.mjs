"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import ActionQueue from "../../assets/js/action_queue.mjs";

defineRuntimeGlobals();

describe("ActionQueue", () => {
  const action1 = "action_1";
  const action2 = "action_2";
  const action3 = "action_3";

  beforeEach(() => {
    ActionQueue.entries = [];
  });

  // The entries here are plain strings, which the runner in another file would read as actions.
  afterEach(() => {
    ActionQueue.entries = [];
  });

  describe("append()", () => {
    it("adds the entries at the end, in their order", () => {
      ActionQueue.enqueue(action1, 3);

      ActionQueue.append([
        {action: action2, epoch: 4},
        {action: action3, epoch: 5},
      ]);

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
        {action: action2, epoch: 4},
        {action: action3, epoch: 5},
      ]);
    });

    it("leaves the queue as it is given no entries", () => {
      ActionQueue.enqueue(action1, 3);

      ActionQueue.append([]);

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
      ]);
    });
  });

  describe("drain()", () => {
    it("returns the entries in their order and empties the queue", () => {
      ActionQueue.enqueue(action1, 3);
      ActionQueue.enqueue(action2, 4);

      assert.deepStrictEqual(ActionQueue.drain(), [
        {action: action1, epoch: 3},
        {action: action2, epoch: 4},
      ]);

      assert.deepStrictEqual(ActionQueue.entries, []);
    });

    it("returns an empty list with no entries", () => {
      assert.deepStrictEqual(ActionQueue.drain(), []);
      assert.deepStrictEqual(ActionQueue.entries, []);
    });
  });

  describe("enqueue()", () => {
    it("appends an entry holding the action and its epoch", () => {
      ActionQueue.enqueue(action1, 3);

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
      ]);
    });

    it("keeps the order of arrival", () => {
      ActionQueue.enqueue(action1, 3);
      ActionQueue.enqueue(action2, 4);

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
        {action: action2, epoch: 4},
      ]);
    });
  });

  describe("removeAt()", () => {
    it("removes and returns the entry at the position", () => {
      ActionQueue.enqueue(action1, 3);
      ActionQueue.enqueue(action2, 4);
      ActionQueue.enqueue(action3, 5);

      assert.deepStrictEqual(ActionQueue.removeAt(1), {
        action: action2,
        epoch: 4,
      });

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
        {action: action3, epoch: 5},
      ]);
    });

    it("returns undefined for a position past the end", () => {
      ActionQueue.enqueue(action1, 3);

      assert.isUndefined(ActionQueue.removeAt(1));
      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
      ]);
    });
  });
});

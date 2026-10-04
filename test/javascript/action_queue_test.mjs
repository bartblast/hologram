"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import ActionQueue from "../../assets/js/action_queue.mjs";

defineRuntimeGlobals();

describe("ActionQueue", () => {
  const action1 = "action_1";
  const action2 = "action_2";

  beforeEach(() => {
    ActionQueue.entries = [];
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

  describe("isEmpty()", () => {
    it("is true with no entries", () => {
      assert.isTrue(ActionQueue.isEmpty());
    });

    it("is false with an entry", () => {
      ActionQueue.enqueue(action1, 3);

      assert.isFalse(ActionQueue.isEmpty());
    });
  });

  describe("peek()", () => {
    it("returns the first entry without removing it", () => {
      ActionQueue.enqueue(action1, 3);
      ActionQueue.enqueue(action2, 4);

      assert.deepStrictEqual(ActionQueue.peek(), {action: action1, epoch: 3});

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: 3},
        {action: action2, epoch: 4},
      ]);
    });

    it("returns undefined with no entries", () => {
      assert.isUndefined(ActionQueue.peek());
    });
  });

  describe("shift()", () => {
    it("removes and returns the first entry", () => {
      ActionQueue.enqueue(action1, 3);
      ActionQueue.enqueue(action2, 4);

      assert.deepStrictEqual(ActionQueue.shift(), {action: action1, epoch: 3});
      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action2, epoch: 4},
      ]);
    });

    it("returns undefined with no entries", () => {
      assert.isUndefined(ActionQueue.shift());
    });
  });
});

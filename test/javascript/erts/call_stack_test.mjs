"use strict";

import {assert} from "../support/helpers.mjs";

import CallStack from "../../../assets/js/erts/call_stack.mjs";

const enumFrame = {
  module: "Enum",
  function: "map",
  arityOrArgs: 2,
  file: "lib/enum.ex",
  line: 1_696,
  errorInfo: null,
};

const myModuleFrame = {
  module: "MyModule",
  function: "my_fun",
  arityOrArgs: 1,
  file: "lib/my_module.ex",
  line: 11,
  errorInfo: null,
};

describe("CallStack", () => {
  beforeEach(() => {
    CallStack.reset();
  });

  describe("peek()", () => {
    it("returns the innermost frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.equal(CallStack.peek(), enumFrame);
    });

    it("doesn't remove the returned frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.peek();

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("returns undefined when the stack is empty", () => {
      assert.isUndefined(CallStack.peek());
    });
  });

  describe("pop()", () => {
    it("removes the innermost frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);
      CallStack.pop();

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("returns the removed frame", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.equal(CallStack.pop(), enumFrame);
    });

    it("returns undefined when the stack is empty", () => {
      assert.isUndefined(CallStack.pop());
    });
  });

  describe("push()", () => {
    it("adds the frame to an empty stack", () => {
      CallStack.push(myModuleFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [myModuleFrame]);
    });

    it("adds the frame as the new innermost one", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [enumFrame, myModuleFrame]);
    });
  });

  describe("reset()", () => {
    it("clears the stack", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);
      CallStack.reset();

      assert.deepStrictEqual(CallStack.snapshot(), []);
    });
  });

  describe("snapshot()", () => {
    it("returns an empty array when the stack is empty", () => {
      assert.deepStrictEqual(CallStack.snapshot(), []);
    });

    it("returns the frames innermost first", () => {
      CallStack.push(myModuleFrame);
      CallStack.push(enumFrame);

      assert.deepStrictEqual(CallStack.snapshot(), [enumFrame, myModuleFrame]);
    });

    it("returns frames by reference", () => {
      CallStack.push(myModuleFrame);

      assert.equal(CallStack.snapshot()[0], myModuleFrame);
    });

    it("returns a copy that a later push doesn't affect", () => {
      CallStack.push(myModuleFrame);

      const snapshot = CallStack.snapshot();
      CallStack.push(enumFrame);

      assert.deepStrictEqual(snapshot, [myModuleFrame]);
    });

    it("returns a copy that a later pop doesn't affect", () => {
      CallStack.push(myModuleFrame);

      const snapshot = CallStack.snapshot();
      CallStack.pop();

      assert.deepStrictEqual(snapshot, [myModuleFrame]);
    });
  });
});

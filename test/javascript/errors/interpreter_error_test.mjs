"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";

defineRuntimeGlobals();

describe("HologramInterpreterError", () => {
  it("throw", () => {
    try {
      throw new HologramInterpreterError("my message");
    } catch (error) {
      assert.instanceOf(error, HologramInterpreterError);
      assert.deepStrictEqual(error.message, "my message");
    }
  });
});

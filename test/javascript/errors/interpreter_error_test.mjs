"use strict";

import {assert, linkModules, unlinkModules} from "../support/helpers.mjs";

import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";

describe("HologramInterpreterError", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  it("throw", () => {
    try {
      throw new HologramInterpreterError("my message");
    } catch (error) {
      assert.instanceOf(error, HologramInterpreterError);
      assert.deepStrictEqual(error.message, "my message");
    }
  });
});

"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import HologramMatchError from "../../../assets/js/errors/match_error.mjs";

defineGlobalErlangAndElixirModules();

describe("HologramMatchError", () => {
  it("throw", () => {
    const value = {a: 1, b: 2};

    try {
      throw new HologramMatchError(value);
    } catch (error) {
      assert.instanceOf(error, HologramMatchError);
      assert.deepStrictEqual(error.value, value);
    }
  });
});

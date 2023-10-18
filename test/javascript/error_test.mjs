"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import HologramError from "../../assets/js/error.mjs";

it("HologramError", () => {
  const struct = {a: 1, b: 2};

  try {
    throw new HologramError(struct);
  } catch (error) {
    assert.instanceOf(error, HologramError);
    assert.deepStrictEqual(error.struct, struct);
  }
});

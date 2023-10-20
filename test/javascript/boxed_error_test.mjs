"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import HologramBoxedError from "../../assets/js/boxed_error.mjs";

it("HologramBoxedError", () => {
  const struct = {a: 1, b: 2};

  try {
    throw new HologramBoxedError(struct);
  } catch (error) {
    assert.instanceOf(error, HologramBoxedError);
    assert.deepStrictEqual(error.struct, struct);
  }
});

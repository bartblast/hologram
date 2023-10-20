"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import HologramMatchError from "../../assets/js/match_error.mjs";

it("HologramMatchError", () => {
  const value = {a: 1, b: 2};

  try {
    throw new HologramMatchError(value);
  } catch (error) {
    assert.instanceOf(error, HologramMatchError);
    assert.deepStrictEqual(error.value, value);
  }
});

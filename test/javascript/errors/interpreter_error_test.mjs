"use strict";

import {assert} from "../../../assets/js/test_support.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";

it("HologramInterpreterError", () => {
  try {
    throw new HologramInterpreterError("my message");
  } catch (error) {
    assert.instanceOf(error, HologramInterpreterError);
    assert.deepStrictEqual(error.message, "my message");
  }
});

"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import HologramError from "../../assets/js/error.mjs";

it("HologramError", () => {
  assert.throw(
    () => {
      throw new HologramError("my message");
    },
    HologramError,
    "my message",
  );
});

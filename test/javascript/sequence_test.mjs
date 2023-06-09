"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import Sequence from "../../assets/js/sequence.mjs";

it("next()", () => {
  assert.equal(Sequence.next(), 1);
  assert.equal(Sequence.next(), 2);
});

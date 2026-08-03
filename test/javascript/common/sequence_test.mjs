"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import Sequence from "../../../assets/js/common/sequence.mjs";

defineRuntimeGlobals();

describe("Sequence", () => {
  it("next()", () => {
    const sequence = new Sequence();

    assert.equal(sequence.next(), 1);
    assert.equal(sequence.next(), 2);
  });

  it("reset()", () => {
    const sequence = new Sequence();

    sequence.next();
    sequence.next();
    sequence.reset();

    assert.equal(sequence.value, 0);
  });
});

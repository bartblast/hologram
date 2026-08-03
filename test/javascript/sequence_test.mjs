"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Sequence from "../../assets/js/sequence.mjs";

defineRuntimeGlobals();

describe("Sequence", () => {
  beforeEach(() => {
    Sequence.reset();
  });

  it("next()", () => {
    assert.equal(Sequence.next(), 1);
    assert.equal(Sequence.next(), 2);
  });

  it("reset()", () => {
    Sequence.value = 123;
    Sequence.reset();

    assert.equal(Sequence.value, 0);
  });
});

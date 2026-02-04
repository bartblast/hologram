"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Sequence from "../../../assets/js/common/sequence.mjs";

defineGlobalErlangAndElixirModules();

describe("Sequence", () => {
  it("next()", () => {
    const sequence = new Sequence();

    assert.equal(sequence.next(), 1);
    assert.equal(sequence.next(), 2);
  });
});

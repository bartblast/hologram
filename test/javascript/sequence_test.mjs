"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Sequence from "../../assets/js/sequence.mjs";

defineGlobalErlangAndElixirModules();

describe("Sequence", () => {
  beforeEach(() => {
    Sequence.value = 0;
  });

  it("next()", () => {
    assert.equal(Sequence.next(), 1);
    assert.equal(Sequence.next(), 2);
  });
});

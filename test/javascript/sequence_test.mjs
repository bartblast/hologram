"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import Sequence from "../../assets/js/sequence.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("Sequence", () => {
  beforeEach(() => {
    Sequence.value = 0;
  });

  it("next()", () => {
    assert.equal(Sequence.next(), 1);
    assert.equal(Sequence.next(), 2);
  });
});

"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import Sequence from "../../assets/js/sequence.mjs";

describe("Sequence", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  beforeEach(() => {
    Sequence.value = 0;
  });

  it("next()", () => {
    assert.equal(Sequence.next(), 1);
    assert.equal(Sequence.next(), 2);
  });
});

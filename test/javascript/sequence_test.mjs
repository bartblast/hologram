"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Sequence from "../../assets/js/sequence.mjs";

before(() => linkModules());
after(() => unlinkModules());

beforeEach(() => {
  Sequence.value = 0;
});

afterEach(() => {
  Sequence.value = 0;
});

it("next()", () => {
  assert.equal(Sequence.next(), 1);
  assert.equal(Sequence.next(), 2);
});

"use strict";

import { assert, assertFrozen, cleanup } from "../support/commons";
beforeEach(() => cleanup())

import String from "../../../assets/js/hologram/elixir/string";
import Type from "../../../assets/js/hologram/type";

describe("to_atom()", () => {
  let result;

  beforeEach(() => {
    const arg = Type.string("test");
    result = String.to_atom(arg);
  });

  it("converts boxed string to boxed atom", () => {
    const expected = Type.atom("test");
    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});

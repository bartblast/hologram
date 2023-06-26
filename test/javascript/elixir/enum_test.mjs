"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Elixir_Enum from "../../../assets/js/elixir/enum.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("count()", () => {
  it("returns the number of items in a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Elixir_Enum.count(list);

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("returns the number of items in a boxed map", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Elixir_Enum.count(map);

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("returns the number of items in a boxed tuple", () => {
    const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
    const result = Elixir_Enum.count(tuple);

    assert.deepStrictEqual(result, Type.integer(2));
  });
});

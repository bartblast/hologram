"use strict";

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/lists_test.exs
// Always update both together.

describe("reverse/1", () => {
  it("returns a list with the elements in the argument in reverse order", () => {
    const arg = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang_Lists["reverse/1"](arg);

    const expected = Type.list([
      Type.integer(3),
      Type.integer(2),
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises FunctionClauseError if the argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Lists["reverse/1"](Type.atom("abc")),
      "FunctionClauseError",
      "no function clause matching in :lists.reverse/1",
    );
  });
});

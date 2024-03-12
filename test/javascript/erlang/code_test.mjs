"use strict";

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../support/helpers.mjs";

import Erlang_Code from "../../../assets/js/erlang/code.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/code_test.exs
// Always update both together.

describe("ensure_loaded/1", () => {
  const fun = Erlang_Code["ensure_loaded/1"];

  it("loaded module", () => {
    const module = Type.alias("String.Chars");
    const result = fun(module);
    const expected = Type.tuple([Type.atom("module"), module]);

    assert.deepStrictEqual(result, expected);
  });

  it("not loaded, non-existing module", () => {
    const module = Type.alias("MyModule");
    const result = fun(module);
    const expected = Type.tuple([Type.atom("error"), Type.atom("nofile")]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises FunctionClauseError if the argument is not an atom", () => {
    assertBoxedError(
      () => fun(Type.integer(1)),
      "FunctionClauseError",
      "no function clause matching in :code.ensure_loaded/1",
    );
  });
});

"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang_Elixir_Aliases from "../../../assets/js/erlang/elixir_aliases.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/elixir_aliases_test.exs
// Always update both together.

describe("concat/1", () => {
  const expectedAlias = Type.alias("Aaa.Bbb.Ccc");

  it("works with atom segments which are Elixir module aliases", () => {
    const segments = Type.list([
      Type.alias("Aaa"),
      Type.alias("Bbb"),
      Type.alias("Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("works with atom segments which are not Elixir module aliases", () => {
    const segments = Type.list([
      Type.atom("Aaa"),
      Type.atom("Bbb"),
      Type.atom("Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("works with binary bitstring segments", () => {
    const segments = Type.list([
      Type.bitstring("Aaa"),
      Type.bitstring("Bbb"),
      Type.bitstring("Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("ignores nil segments", () => {
    const segments = Type.list([
      Type.alias("Aaa"),
      Type.nil(),
      Type.alias("Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);
    const expectedAlias = Type.alias("Aaa.Ccc");

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("removes the first dot character from the segment before joining segments with a dot character", () => {
    const segments = Type.list([
      Type.bitstring("...Aaa"),
      Type.bitstring("...Bbb"),
      Type.bitstring("...Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);
    const expectedAlias = Type.alias("..Aaa...Bbb...Ccc");

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("doesn't prepend 'Elixir' segment if it is already present as the first element", () => {
    const segments = Type.list([
      Type.bitstring("Elixir"),
      Type.alias("Aaa"),
      Type.alias("Bbb"),
      Type.alias("Ccc"),
    ]);

    const result = Erlang_Elixir_Aliases["concat/1"](segments);

    assert.deepStrictEqual(result, expectedAlias);
  });

  it("raises FunctionClauseError if the argument is not a list", () => {
    assertBoxedError(
      () => Erlang_Elixir_Aliases["concat/1"](Type.atom("abc")),
      "FunctionClauseError",
      "no function clause matching in :elixir_aliases.do_concat/2",
    );
  });

  it("raises FunctionClauseError if any non-binary bitstring segments are present", () => {
    const segments = Type.list([
      Type.bitstring("Aaa"),
      Type.bitstring([
        Type.bitstringSegment(Type.integer(1), {
          type: "integer",
          size: Type.integer(2),
        }),
      ]),
      Type.bitstring("Ccc"),
    ]);

    assertBoxedError(
      () => Erlang_Elixir_Aliases["concat/1"](segments),
      "FunctionClauseError",
      "no function clause matching in :elixir_aliases.do_concat/2",
    );
  });

  it("raises FunctionClauseError if any non-atom or non-bitstring segments are present", () => {
    const segments = Type.list([
      Type.bitstring("Aaa"),
      Type.integer(123),
      Type.bitstring("Ccc"),
    ]);

    assertBoxedError(
      () => Erlang_Elixir_Aliases["concat/1"](segments),
      "FunctionClauseError",
      "no function clause matching in :elixir_aliases.do_concat/2",
    );
  });
});

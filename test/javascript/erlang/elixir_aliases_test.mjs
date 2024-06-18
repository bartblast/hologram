"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Elixir_Aliases from "../../../assets/js/erlang/elixir_aliases.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/elixir_aliases_test.exs
// Always update both together.

describe("Erlang_Elixir_Aliases", () => {
  describe("concat/1", () => {
    const concat = Erlang_Elixir_Aliases["concat/1"];
    const expectedAlias = Type.alias("Aaa.Bbb.Ccc");

    it("works with atom segments which are Elixir module aliases", () => {
      const segments = Type.list([
        Type.alias("Aaa"),
        Type.alias("Bbb"),
        Type.alias("Ccc"),
      ]);

      const result = concat(segments);

      assert.deepStrictEqual(result, expectedAlias);
    });

    it("works with atom segments which are not Elixir module aliases", () => {
      const segments = Type.list([
        Type.atom("Aaa"),
        Type.atom("Bbb"),
        Type.atom("Ccc"),
      ]);

      const result = concat(segments);

      assert.deepStrictEqual(result, expectedAlias);
    });

    it("works with binary bitstring segments", () => {
      const segments = Type.list([
        Type.bitstring("Aaa"),
        Type.bitstring("Bbb"),
        Type.bitstring("Ccc"),
      ]);

      const result = concat(segments);

      assert.deepStrictEqual(result, expectedAlias);
    });

    it("ignores nil segments", () => {
      const segments = Type.list([
        Type.alias("Aaa"),
        Type.nil(),
        Type.alias("Ccc"),
      ]);

      const result = concat(segments);
      const expectedAlias = Type.alias("Aaa.Ccc");

      assert.deepStrictEqual(result, expectedAlias);
    });

    it("removes the first dot character from the segment before joining segments with a dot character", () => {
      const segments = Type.list([
        Type.bitstring("...Aaa"),
        Type.bitstring("...Bbb"),
        Type.bitstring("...Ccc"),
      ]);

      const result = concat(segments);
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

      const result = concat(segments);

      assert.deepStrictEqual(result, expectedAlias);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      assertBoxedError(
        () => concat(Type.atom("abc")),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          Type.atom("abc"),
          Type.bitstring("Elixir"),
        ]),
      );
    });

    it("raises FunctionClauseError if a non-binary bitstring segment is present", () => {
      const bitstringSize2 = Type.bitstring([
        Type.bitstringSegment(Type.integer(1), {
          type: "integer",
          size: Type.integer(2),
        }),
      ]);

      const segments = Type.list([
        Type.bitstring("Aaa"),
        bitstringSize2,
        Type.bitstring("Ccc"),
      ]);

      assertBoxedError(
        () => concat(segments),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          Type.list([bitstringSize2, Type.bitstring("Ccc")]),
          Type.bitstring("Elixir.Aaa"),
        ]),
      );
    });

    it("raises FunctionClauseError if any non-atom or non-bitstring segments are present", () => {
      const segments = Type.list([
        Type.bitstring("Aaa"),
        Type.integer(123),
        Type.bitstring("Ccc"),
      ]);

      assertBoxedError(
        () => concat(segments),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          Type.list([Type.integer(123), Type.bitstring("Ccc")]),
          Type.bitstring("Elixir.Aaa"),
        ]),
      );
    });

    it("raises FunctionClauseError if invalid segment is present and the segments contain 'Elixir' as the first segment", () => {
      const segments = Type.list([
        Type.bitstring("Elixir"),
        Type.bitstring("Aaa"),
        Type.integer(123),
        Type.bitstring("Ccc"),
      ]);

      assertBoxedError(
        () => concat(segments),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          Type.list([Type.integer(123), Type.bitstring("Ccc")]),
          Type.bitstring("Elixir.Aaa"),
        ]),
      );
    });

    it("raises FunctionClauseError if invalid segment is present as the first segment", () => {
      const segments = Type.list([Type.integer(123), Type.bitstring("Ccc")]);

      assertBoxedError(
        () => concat(segments),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          Type.list([Type.integer(123), Type.bitstring("Ccc")]),
          Type.bitstring("Elixir"),
        ]),
      );
    });
  });
});

"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const binary = Bitstring.fromBytes([5, 19, 72, 33]);
    const at = Erlang_Binary["at/2"];

    it("returns first byte", () => {
      const result = at(binary, Type.integer(0));
      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns middle byte", () => {
      const result = at(binary, Type.integer(1));
      assert.deepStrictEqual(result, Type.integer(19));
    });

    it("returns last byte", () => {
      const result = at(binary, Type.integer(3));
      assert.deepStrictEqual(result, Type.integer(33));
    });

    it("raises ArgumentError when position is out of range", () => {
      const pos = Type.integer(4);

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises FunctionClauseError when subject is nil", () => {
      const subject = Type.nil();
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when bitstring is not a binary", () => {
      const subject = Type.bitstring([1, 0, 1]);
      const pos = Type.integer(0);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when position is nil", () => {
      const subject = Type.bitstring([1, 0, 1]);
      const pos = Type.nil();

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [subject, pos],
      );

      assertBoxedError(
        () => at(subject, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });

    it("raises FunctionClauseError when position is negative", () => {
      const pos = Type.integer(-1);

      const expectedMessage = Interpreter.buildFunctionClauseErrorMsg(
        ":binary.at/2",
        [binary, pos],
      );

      assertBoxedError(
        () => at(binary, pos),
        "FunctionClauseError",
        expectedMessage,
      );
    });
  });
});

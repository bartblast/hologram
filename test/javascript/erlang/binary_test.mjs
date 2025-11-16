"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/ex_js_consistency/erlang/binary_test.exs
// Always update both together.

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const at = Erlang_Binary["at/2"];

    const binary = Bitstring.fromBytes([5, 19, 72, 33]);

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
        "argument error",
      );
    });

    it("raises ArgumentError when subject is nil", () => {
      const subject = Type.nil();

      assertBoxedError(
        () => at(subject, Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError when bitstring is not a binary", () => {
      const subject = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => at(subject, Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError when position is nil", () => {
      const pos = Type.nil();

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError when position is negative", () => {
      const pos = Type.integer(-1);

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });
  });

  describe("copy/2", () => {
    const testedFun = Erlang_Binary["copy/2"];

    it("copies an empty, text-based binary zero times", () => {
      const binary = Bitstring.fromText("");
      const n = Type.integer(0);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("copies an empty, text-based binary a single time", () => {
      const binary = Bitstring.fromText("");
      const n = Type.integer(1);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("copies an empty, text-based binary multiple times", () => {
      const binary = Bitstring.fromText("");
      const n = Type.integer(3);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("copies an empty, bytes-based binary zero times", () => {
      const binary = Bitstring.fromBytes([]);
      const n = Type.integer(0);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromBytes([]));
    });

    it("copies an empty, bytes-based binary a single time", () => {
      const binary = Bitstring.fromBytes([]);
      const n = Type.integer(1);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromBytes([]));
    });

    it("copies an empty, bytes-based binary multiple times", () => {
      const binary = Bitstring.fromBytes([]);
      const n = Type.integer(3);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromBytes([]));
    });

    it("copies a non-empty, text-based binary zero times", () => {
      const binary = Bitstring.fromText("hello");
      const n = Type.integer(0);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("copies a non-empty, text-based binary a single time", () => {
      const binary = Bitstring.fromText("test");
      const n = Type.integer(1);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText("test"));
    });

    it("copies a non-empty, text-based binary multiple times", () => {
      const binary = Bitstring.fromText("hello");
      const n = Type.integer(3);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromText("hellohellohello"));
    });

    it("copies a non-empty, bytes-based binary zero times", () => {
      const binary = Bitstring.fromBytes([65, 66, 67]);
      const n = Type.integer(0);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromBytes([]));
    });

    it("copies a non-empty, bytes-based binary a single time", () => {
      const binary = Bitstring.fromBytes([65, 66, 67]);
      const n = Type.integer(1);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(result, Bitstring.fromBytes([65, 66, 67]));
    });

    it("copies a non-empty, bytes-based binary multiple times", () => {
      const binary = Bitstring.fromBytes([65, 66, 67]);
      const n = Type.integer(2);
      const result = testedFun(binary, n);

      assertBoxedStrictEqual(
        result,
        Bitstring.fromBytes([65, 66, 67, 65, 66, 67]),
      );
    });

    it("raises ArgumentError if the first argument is not a bitstring", () => {
      const notBinary = Type.atom("not_binary");
      const n = Type.integer(2);

      assertBoxedError(
        () => testedFun(notBinary, n),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
      // Create a bitstring with 3 bits (not byte-aligned)
      const bitstring = Type.bitstring([1, 0, 1]);
      const n = Type.integer(2);

      assertBoxedError(
        () => testedFun(bitstring, n),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError if the second argument is not an integer", () => {
      const binary = Bitstring.fromText("test");
      const notInteger = Type.atom("not_integer");

      assertBoxedError(
        () => testedFun(binary, notInteger),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if count is negative", () => {
      const binary = Bitstring.fromText("test");
      const n = Type.integer(-1);

      assertBoxedError(
        () => testedFun(binary, n),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });
  });
});

"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Bitstring from "../../../assets/js/bitstring.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Binary", () => {
  describe("first/1", () => {
    const first = Erlang_Binary["first/1"];

    it("raises ArgumentError if the first argument is a integer", () => {
      assertBoxedError(
        () => first(Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a float", () => {
      assertBoxedError(
        () => first(Type.float(3.14)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is an atom", () => {
      assertBoxedError(
        () => first(Type.atom("test")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a list", () => {
      assertBoxedError(
        () => first(Type.list([Type.integer(1), Type.integer(2)])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a tuple", () => {
      assertBoxedError(
        () => first(Type.tuple([Type.integer(1), Type.integer(2)])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a map", () => {
      assertBoxedError(
        () => first(Type.map([[Type.atom("key"), Type.integer(1)]])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
      assertBoxedError(
        () => first(Type.bitstring([1, 0, 1])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError if the first argument is a zero-sized binary", () => {
      assertBoxedError(
        () => first(Type.bitstring([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    });

    it("raises ArgumentError if the first argument is a zero-sized text", () => {
      assertBoxedError(
        () => first(Bitstring.fromText("")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    });

    it("return first byte of a binary", () => {
      const segment = Bitstring.fromBytes([5, 4, 3]);

      const result = first(segment);

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns first byte of a text-based bitstring", () => {
      const segment = Bitstring.fromText("ELIXIR");
      const result = first(segment);

      assert.deepStrictEqual(result, Type.integer(69));
    });

    it("returns first byte of a single-byte binary", () => {
      const segment = Bitstring.fromBytes([42]);
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns first byte of a single-character text", () => {
      const segment = Bitstring.fromText("Z");
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(90));
    });

    it("returns first byte of a large binary", () => {
      const bytes = Array(1000).fill(0);
      bytes[0] = 123;
      const segment = Bitstring.fromBytes(bytes);
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(123));
    });

    it("returns first byte of binary created from float literal", () => {
      const segment = {
        value: Type.float(3.14),
        size: null,
        unit: 1,
        type: "float",
        endianness: "big",
        signedness: "unsigned",
      };

      const bitstring = Bitstring.fromSegmentWithFloatValue(segment);
      const result = first(bitstring);

      assert.deepStrictEqual(result, Type.integer(64));
    });

    it("returns 0 when byte value wraps around (256 mod 256)", () => {
      const segment = Bitstring.fromBytes([256]);
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 255 when first byte is -1 (two's complement wraparound)", () => {
      const segment = Bitstring.fromBytes([-1, 43]);
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(255));
    });

    it("returns first byte of UTF-8 multi-byte character", () => {
      const segment = Bitstring.fromText("é");
      const result = first(segment);
      assert.deepStrictEqual(result, Type.integer(195));
    });
  });
});

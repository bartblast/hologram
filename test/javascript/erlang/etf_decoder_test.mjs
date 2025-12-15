"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("binary_to_term/1", () => {
  const testedFun = Erlang["binary_to_term/1"];

  describe("integers", () => {
    it("decodes small positive integer (SMALL_INTEGER_EXT)", () => {
      // :erlang.term_to_binary(42) = <<131, 97, 42>>
      const binary = Bitstring.fromBytes(new Uint8Array([131, 97, 42]));
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("decodes small positive integer (max value 255)", () => {
      // :erlang.term_to_binary(255) = <<131, 97, 255>>
      const binary = Bitstring.fromBytes(new Uint8Array([131, 97, 255]));
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(255));
    });

    it("decodes positive integer (INTEGER_EXT)", () => {
      // :erlang.term_to_binary(1000) = <<131, 98, 0, 0, 3, 232>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 98, 0, 0, 3, 232]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(1000));
    });

    it("decodes negative integer (INTEGER_EXT)", () => {
      // :erlang.term_to_binary(-100) = <<131, 98, 255, 255, 255, 156>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 98, 255, 255, 255, 156]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(-100));
    });

    it("decodes large positive integer (SMALL_BIG_EXT)", () => {
      // :erlang.term_to_binary(1000000000000) = <<131, 110, 5, 0, 0, 16, 165, 212, 232>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 110, 5, 0, 0, 16, 165, 212, 232]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(1000000000000n));
    });

    it("decodes large negative integer (SMALL_BIG_EXT)", () => {
      // :erlang.term_to_binary(-1000000000000) = <<131, 110, 5, 1, 0, 16, 165, 212, 232>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 110, 5, 1, 0, 16, 165, 212, 232]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.integer(-1000000000000n));
    });
  });

  describe("atoms", () => {
    it("decodes UTF-8 atom (SMALL_ATOM_UTF8_EXT)", () => {
      // :erlang.term_to_binary(:test) = <<131, 119, 4, 116, 101, 115, 116>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 119, 4, 116, 101, 115, 116]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.atom("test"));
    });

    it("decodes longer atom", () => {
      // :erlang.term_to_binary(:test_atom) = <<131, 119, 9, 116, 101, 115, 116, 95, 97, 116, 111, 109>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([
          131, 119, 9, 116, 101, 115, 116, 95, 97, 116, 111, 109,
        ]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.atom("test_atom"));
    });

    it("decodes boolean atoms", () => {
      // :erlang.term_to_binary(true) = <<131, 119, 4, 116, 114, 117, 101>>
      const trueBinary = Bitstring.fromBytes(
        new Uint8Array([131, 119, 4, 116, 114, 117, 101]),
      );
      const trueResult = testedFun(trueBinary);
      assert.deepStrictEqual(trueResult, Type.atom("true"));

      // :erlang.term_to_binary(false) = <<131, 119, 5, 102, 97, 108, 115, 101>>
      const falseBinary = Bitstring.fromBytes(
        new Uint8Array([131, 119, 5, 102, 97, 108, 115, 101]),
      );
      const falseResult = testedFun(falseBinary);
      assert.deepStrictEqual(falseResult, Type.atom("false"));
    });
  });

  describe("binaries", () => {
    it("decodes binary string (BINARY_EXT)", () => {
      // :erlang.term_to_binary("hello") = <<131, 109, 0, 0, 0, 5, 104, 101, 108, 108, 111>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 109, 0, 0, 0, 5, 104, 101, 108, 108, 111]),
      );
      const result = testedFun(binary);
      assertBoxedStrictEqual(result, Type.bitstring("hello"));
    });

    it("decodes empty binary", () => {
      // :erlang.term_to_binary("") = <<131, 109, 0, 0, 0, 0>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 109, 0, 0, 0, 0]),
      );
      const result = testedFun(binary);
      assertBoxedStrictEqual(result, Type.bitstring(""));
    });
  });

  describe("tuples", () => {
    it("decodes small tuple (SMALL_TUPLE_EXT)", () => {
      // :erlang.term_to_binary({1, 2, 3}) = <<131, 104, 3, 97, 1, 97, 2, 97, 3>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 104, 3, 97, 1, 97, 2, 97, 3]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("decodes empty tuple", () => {
      // :erlang.term_to_binary({}) = <<131, 104, 0>>
      const binary = Bitstring.fromBytes(new Uint8Array([131, 104, 0]));
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.tuple([]));
    });

    it("decodes nested tuple", () => {
      // :erlang.term_to_binary({1, {2, 3}}) = <<131, 104, 2, 97, 1, 104, 2, 97, 2, 97, 3>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 104, 2, 97, 1, 104, 2, 97, 2, 97, 3]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.integer(1),
          Type.tuple([Type.integer(2), Type.integer(3)]),
        ]),
      );
    });
  });

  describe("lists", () => {
    it("decodes empty list (NIL_EXT)", () => {
      // :erlang.term_to_binary([]) = <<131, 106>>
      const binary = Bitstring.fromBytes(new Uint8Array([131, 106]));
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.list([]));
    });

    it("decodes string list (STRING_EXT)", () => {
      // :erlang.term_to_binary([1, 2, 3]) = <<131, 107, 0, 3, 1, 2, 3>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 107, 0, 3, 1, 2, 3]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("decodes proper list (LIST_EXT)", () => {
      // :erlang.term_to_binary([100, 200, 300]) = <<131, 108, 0, 0, 0, 3, 97, 100, 98, 0, 0, 0, 200, 98, 0, 0, 1, 44, 106>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([
          131, 108, 0, 0, 0, 3, 97, 100, 98, 0, 0, 0, 200, 98, 0, 0, 1, 44, 106,
        ]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(100), Type.integer(200), Type.integer(300)]),
      );
    });
  });

  describe("maps", () => {
    it("decodes empty map", () => {
      // :erlang.term_to_binary(%{}) = <<131, 116, 0, 0, 0, 0>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([131, 116, 0, 0, 0, 0]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(result, Type.map([]));
    });

    it("decodes map with atom keys", () => {
      // :erlang.term_to_binary(%{a: 1, b: 2}) = <<131, 116, 0, 0, 0, 2, 119, 1, 97, 97, 1, 119, 1, 98, 97, 2>>
      const binary = Bitstring.fromBytes(
        new Uint8Array([
          131, 116, 0, 0, 0, 2, 119, 1, 97, 97, 1, 119, 1, 98, 97, 2,
        ]),
      );
      const result = testedFun(binary);
      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      );
    });
  });

  describe("complex nested structures", () => {
    it("decodes Code.fetch_docs/1 style tuple", () => {
      // :erlang.term_to_binary({:docs_v1, 1, :elixir, "text/markdown", %{}, %{}, []})
      const binary = Bitstring.fromBytes(
        new Uint8Array([
          131, 104, 7, 119, 7, 100, 111, 99, 115, 95, 118, 49, 97, 1, 119, 6,
          101, 108, 105, 120, 105, 114, 109, 0, 0, 0, 13, 116, 101, 120, 116,
          47, 109, 97, 114, 107, 100, 111, 119, 110, 116, 0, 0, 0, 0, 116, 0, 0,
          0, 0, 106,
        ]),
      );
      const result = testedFun(binary);

      assertBoxedStrictEqual(
        result,
        Type.tuple([
          Type.atom("docs_v1"),
          Type.integer(1),
          Type.atom("elixir"),
          Type.bitstring("text/markdown"),
          Type.map([]),
          Type.map([]),
          Type.list([]),
        ]),
      );
    });
  });

  describe("error handling", () => {
    it("raises ArgumentError if argument is not a binary", () => {
      assertBoxedError(
        () => testedFun(Type.atom("test")),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
      );
    });

    it("raises ArgumentError if binary has invalid version byte", () => {
      const binary = Bitstring.fromBytes(new Uint8Array([130, 97, 42])); // Wrong version
      assertBoxedError(
        () => testedFun(binary),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: invalid external representation of a term\n",
      );
    });

    it("raises ArgumentError if binary is truncated", () => {
      const binary = Bitstring.fromBytes(new Uint8Array([131])); // Only version byte
      assertBoxedError(
        () => testedFun(binary),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: invalid external representation of a term\n",
      );
    });
  });
});

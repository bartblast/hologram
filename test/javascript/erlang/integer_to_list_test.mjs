"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Integer_To_List from "../../../assets/js/erlang/integer_to_list.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Integer_To_List", () => {
  const int_to_list_1 = Erlang_Integer_To_List["integer_to_list/1"];
  const int_to_list_2 = Erlang_Integer_To_List["integer_to_list/2"];

  // ========================================
  // integer_to_list/1
  // ========================================

  describe("integer_to_list/1", () => {
    it("positive integer", () => {
      const result = int_to_list_1(Type.integer(77));
      //   assert.strictEqual(result.value, "77");
      assert.strictEqual(Bitstring.toText(result), "77");
    });

    it("negative integer", () => {
      const result = int_to_list_1(Type.integer(-123));
      assert.strictEqual(Bitstring.toText(result), "-123");
    });

    it("zero", () => {
      const result = int_to_list_1(Type.integer(0));
      assert.strictEqual(Bitstring.toText(result), "0");
    });

    it("large integer", () => {
      const big = BigInt("12345678901234567890");
      const result = int_to_list_1(Type.integer(big));
      assert.strictEqual(Bitstring.toText(result), "12345678901234567890");
    });

    it("does not generate leading plus sign", () => {
      const result = int_to_list_1(Type.integer(+10));
      assert.strictEqual(Bitstring.toText(result), "10");
    });

    it("negative zero outputs '0'", () => {
      const result = int_to_list_1(Type.integer(-0));
      assert.strictEqual(Bitstring.toText(result), "0");
    });

    it("raises error for non-integer", () => {
      assertBoxedError(
        () => int_to_list_1(Type.float(3.14)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: expected an integer\n"
      );
    });
  });

  // ========================================
  // integer_to_list/2
  // ========================================

  describe("integer_to_list/2", () => {
    it("base 10 standard conversion", () => {
      const result = int_to_list_2(Type.integer(1234), Type.integer(10));
      assert.strictEqual(Bitstring.toText(result), "1234");
    });

    it("base 2 (binary)", () => {
      const result = int_to_list_2(Type.integer(10), Type.integer(2));
      assert.strictEqual(Bitstring.toText(result), "1010");
    });

    it("base 16 (hex uppercase)", () => {
      const result = int_to_list_2(Type.integer(1023), Type.integer(16));
      assert.strictEqual(Bitstring.toText(result), "3FF");
    });

    it("base 36 upper boundary", () => {
      const r1 = int_to_list_2(Type.integer(35), Type.integer(36));
      const r2 = int_to_list_2(Type.integer(36), Type.integer(36));
      assert.strictEqual(Bitstring.toText(r1), "Z");
      assert.strictEqual(Bitstring.toText(r2), "10");
    });

    it("base 2 lower boundary", () => {
      const result = int_to_list_2(Type.integer(1), Type.integer(2));
      assert.strictEqual(Bitstring.toText(result), "1");
    });

    it("negative integer in base 2", () => {
      const result = int_to_list_2(Type.integer(-10), Type.integer(2));
      assert.strictEqual(Bitstring.toText(result), "-1010");
    });

    it("negative integer in base 16", () => {
      const result = int_to_list_2(Type.integer(-255), Type.integer(16));
      assert.strictEqual(Bitstring.toText(result), "-FF");
    });

    it("large integer with base conversion", () => {
      const big = BigInt("4294967295");
      const result = int_to_list_2(Type.integer(big), Type.integer(16));
      assert.strictEqual(Bitstring.toText(result), "FFFFFFFF");
    });

    it("zero with any base", () => {
      const r1 = int_to_list_2(Type.integer(0), Type.integer(2));
      const r2 = int_to_list_2(Type.integer(0), Type.integer(36));
      assert.strictEqual(Bitstring.toText(r1), "0");
      assert.strictEqual(Bitstring.toText(r2), "0");
    });

    it("large negative integer with base conversion", () => {
      const big = BigInt("-4294967295");
      const result = int_to_list_2(Type.integer(big), Type.integer(16));
      assert.strictEqual(Bitstring.toText(result), "-FFFFFFFF");
    });

    it("negative integer with base 36", () => {
      const result = int_to_list_2(Type.integer(-35), Type.integer(36));
      assert.strictEqual(Bitstring.toText(result), "-Z");
    });

    // ---------------------------------------
    // ERROR CASES
    // ---------------------------------------

    it("raises error for base < 2", () => {
      assertBoxedError(
        () => int_to_list_2(Type.integer(10), Type.integer(1)),
        "ErlangError",
        "badarg"
      );
    });

    it("raises error for base > 36", () => {
      assertBoxedError(
        () => int_to_list_2(Type.integer(10), Type.integer(37)),
        "ErlangError",
        "badarg"
      );
    });

    it("raises error when first arg is not integer", () => {
      assertBoxedError(
        () => int_to_list_2(Type.float(3.14), Type.integer(10)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: expected an integer\n"
      );
    });

    it("raises error when second arg is not integer", () => {
      assertBoxedError(
        () => int_to_list_2(Type.integer(10), Type.float(3.5)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 2nd argument: expected an integer\n"
      );
    });

    it("raises when first argument is float even with valid base", () => {
      assertBoxedError(
        () => int_to_list_2(Type.float(12.0), Type.integer(16)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: expected an integer\n"
      );
    });
  });
});

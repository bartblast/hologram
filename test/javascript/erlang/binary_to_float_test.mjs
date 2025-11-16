"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary_To_Float from "../../../assets/js/erlang/binary_to_float.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Binary_To_Float", () => {
  describe("binary_to_float/1", () => {
    const binary_to_float = Erlang_Binary_To_Float["binary_to_float/1"];

    // ------------------------------
    // Success cases
    // ------------------------------
    it("converts a correct binary to a float", () => {
      const result = binary_to_float(Type.bitstring("10.5"));

      assert.isTrue(Type.isFloat(result));
      assert.strictEqual(result.value, 10.5);
    });

    it("parses scientific notation", () => {
      const result = binary_to_float(Type.bitstring("2.2017764e+1"));

      assert.isTrue(Type.isFloat(result));
      assert.strictEqual(result.value, 22.017764);
    });

    it("parses negative float", () => {
      const result = binary_to_float(Type.bitstring("-3.14"));

      assert.isTrue(Type.isFloat(result));
      assert.strictEqual(result.value, -3.14);
    });

    it("parses float with leading zeros", () => {
      const r = binary_to_float(Type.bitstring("00012.34"));
      assert.strictEqual(r.value, 12.34);
    });

    it("parses + sign float", () => {
      const r = binary_to_float(Type.bitstring("+15.5"));
      assert.strictEqual(r.value, 15.5);
    });

    it("parses uppercase E scientific notation", () => {
      const r = binary_to_float(Type.bitstring("1.2E3"));
      assert.strictEqual(r.value, 1200.0);
    });

    it("parses negative exponent", () => {
      const r = binary_to_float(Type.bitstring("1.23e-3"));
      assert.strictEqual(r.value, 0.00123);
    });

    it("parses negative zero", () => {
      const result = binary_to_float(Type.bitstring("-0.0"));
      assert.isTrue(Interpreter.isEqual(result, Type.float(-0.0)));
    });

    // ------------------------------
    // Error Cases
    // ------------------------------
    it("raises argument error if input is not a binary", () => {
      const term = Type.integer(123);

      assertBoxedError(
        () => binary_to_float(term),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: expected a binary\n"
      );
    });

    it("raises badarg when float contains underscores", () => {
      const bin = Type.bitstring("1_000.5");

      assertBoxedError(() => binary_to_float(bin), "ErlangError", "badarg");
    });

    it("raises badarg for invalid float format", () => {
      const bin = Type.bitstring("12.3.4");

      assertBoxedError(() => binary_to_float(bin), "ErlangError", "badarg");
    });

    it("raises badarg for non-numeric text", () => {
      const bin = Type.bitstring("abc");

      assertBoxedError(() => binary_to_float(bin), "ErlangError", "badarg");
    });

    it("rejects empty binary", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("")),
        "ErlangError",
        "badarg"
      );
    });

    it("rejects decimal point only", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring(".")),
        "ErlangError",
        "badarg"
      );
    });

    it("rejects leading dot such as .5", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring(".5")),
        "ErlangError",
        "badarg"
      );
    });

    it("rejects trailing dot such as 5.", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("5.")),
        "ErlangError",
        "badarg"
      );
    });

    it("rejects scientific notation without a fraction like 3e10", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("3e10")),
        "ErlangError",
        "badarg"
      );
    });

    it("raises badarg on trailing exponent marker", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("2e")),
        "ErlangError",
        "badarg"
      );
    });

    it("raises badarg on whitespace around the number", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring(" 12.3")),
        "ErlangError",
        "badarg"
      );
    });

    it("raises badarg on multiple exponent markers", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("1e2e3")),
        "ErlangError",
        "badarg"
      );
    });

    it("raises badarg on Infinity text", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("Infinity")),
        "ErlangError",
        "badarg"
      );
    });

    it("raises badarg on hex-style JS float", () => {
      assertBoxedError(
        () => binary_to_float(Type.bitstring("0x1.fp2")),
        "ErlangError",
        "badarg"
      );
    });

    it("rejects non-UTF-8 binary", () => {
      const bin = Bitstring.fromBits([0xff, 0xff, 0xff]);

      assertBoxedError(
        () => binary_to_float(bin),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 1st argument: expected a binary\n"
      );
    });
  });
});

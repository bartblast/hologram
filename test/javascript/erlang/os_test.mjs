"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Os from "../../../assets/js/erlang/os.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Os", () => {
  describe("system_time/0", () => {
    const systemTime = Erlang_Os["system_time/0"];

    it("returns an integer", () => {
      const result = systemTime();
      assert(Type.isInteger(result));
    });

    it("returns a positive integer", () => {
      const result = systemTime();
      assert(result.value > 0n);
    });

    it("returns nanoseconds since epoch", () => {
      const result = systemTime();
      const now = BigInt(Date.now()) * BigInt(1000000);
      // Allow 100ms (100000000 nanoseconds) difference for test execution
      assert(Math.abs(Number(result.value - now)) < 100000000);
    });
  });

  describe("system_time/1", () => {
    const systemTime = Erlang_Os["system_time/1"];

    it("returns an integer with millisecond atom unit", () => {
      const result = systemTime(Type.atom("millisecond"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns milliseconds with millisecond atom unit", () => {
      const result = systemTime(Type.atom("millisecond"));
      const now = BigInt(Date.now());
      // Allow 100ms difference
      assert(Math.abs(Number(result.value - now)) < 100);
    });

    it("returns an integer with second atom unit", () => {
      const result = systemTime(Type.atom("second"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns seconds with second atom unit", () => {
      const result = systemTime(Type.atom("second"));
      const nowSeconds = BigInt(Math.floor(Date.now() / 1000));
      // Allow 1 second difference
      assert(Math.abs(Number(result.value - nowSeconds)) <= 1);
    });

    it("returns an integer with microsecond atom unit", () => {
      const result = systemTime(Type.atom("microsecond"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns microseconds with microsecond atom unit", () => {
      const result = systemTime(Type.atom("microsecond"));
      const nowMicroseconds = BigInt(Date.now()) * BigInt(1000);
      // Allow 100000 microseconds (100ms) difference
      assert(Math.abs(Number(result.value - nowMicroseconds)) < 100000);
    });

    it("returns an integer with nanosecond atom unit", () => {
      const result = systemTime(Type.atom("nanosecond"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns nanoseconds with nanosecond atom unit", () => {
      const result = systemTime(Type.atom("nanosecond"));
      const nowNanoseconds = BigInt(Date.now()) * BigInt(1000000);
      // Allow 100000000 nanoseconds (100ms) difference
      assert(Math.abs(Number(result.value - nowNanoseconds)) < 100000000);
    });

    it("returns an integer with native atom unit", () => {
      const result = systemTime(Type.atom("native"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns nanoseconds with native atom unit", () => {
      const result = systemTime(Type.atom("native"));
      const now = BigInt(Date.now()) * BigInt(1000000);
      // Allow 100ms (100000000 nanoseconds) difference
      assert(Math.abs(Number(result.value - now)) < 100000000);
    });

    it("returns an integer with perf_counter atom unit", () => {
      const result = systemTime(Type.atom("perf_counter"));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns epoch-based nanoseconds with perf_counter atom unit", () => {
      const result = systemTime(Type.atom("perf_counter"));
      const now = BigInt(Date.now()) * BigInt(1000000);
      // Allow 100ms (100000000 nanoseconds) difference for test execution
      // perf_counter should be epoch-based like other units
      assert(Math.abs(Number(result.value - now)) < 100000000);
    });

    it("returns an integer with numeric unit", () => {
      const result = systemTime(Type.integer(1000n));
      assert(Type.isInteger(result));
      assert(result.value > 0n);
    });

    it("returns milliseconds with numeric unit 1000 (parts per second)", () => {
      const result = systemTime(Type.integer(1000n));
      const now = BigInt(Date.now());
      // Allow 100ms difference
      assert(Math.abs(Number(result.value - now)) < 100);
    });

    it("returns seconds with numeric unit 1", () => {
      const result = systemTime(Type.integer(1n));
      const nowSeconds = BigInt(Math.floor(Date.now() / 1000));
      // Allow 1 second difference
      assert(Math.abs(Number(result.value - nowSeconds)) <= 1);
    });

    it("returns nanoseconds with numeric unit 1000000000", () => {
      const result = systemTime(Type.integer(1000000000n));
      const nowNanoseconds = BigInt(Date.now()) * BigInt(1000000);
      // Allow 100ms (100000000 nanoseconds) difference
      assert(Math.abs(Number(result.value - nowNanoseconds)) < 100000000);
    });

    it("raises ArgumentError if unit is not an atom or integer", () => {
      assertBoxedError(
        () => systemTime(Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit atom is invalid", () => {
      assertBoxedError(
        () => systemTime(Type.atom("invalid_unit")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit is a float", () => {
      assertBoxedError(
        () => systemTime(Type.float(1.5)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit is a bitstring", () => {
      assertBoxedError(
        () => systemTime(Type.bitstring("test")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit is a tuple", () => {
      assertBoxedError(
        () => systemTime(Type.tuple([Type.atom("test")])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit is zero integer", () => {
      assertBoxedError(
        () => systemTime(Type.integer(0n)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError if unit is negative integer", () => {
      assertBoxedError(
        () => systemTime(Type.integer(-1n)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });
  });
});

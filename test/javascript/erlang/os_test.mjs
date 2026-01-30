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

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/os_test.exs
// Always update both together.

describe("Erlang_Os", () => {
  describe("system_time/0", () => {
    const systemTime = Erlang_Os["system_time/0"];

    it("returns current system time in native time unit (nanoseconds)", () => {
      const beforeMs = Date.now();
      const result = systemTime();
      const afterMs = Date.now();

      assert.isTrue(Type.isInteger(result));
      assert.isAtLeast(result.value, BigInt(beforeMs) * 1_000_000n);
      assert.isAtMost(result.value, BigInt(afterMs + 1) * 1_000_000n);
    });
  });

  describe("system_time/1", () => {
    const systemTime = Erlang_Os["system_time/1"];

    it("with valid atom unit", () => {
      const result = systemTime(Type.atom("second"));

      assert.isTrue(Type.isInteger(result));
    });

    it("with valid integer unit", () => {
      const result = systemTime(Type.integer(1000));

      assert.isTrue(Type.isInteger(result));
    });

    it("applies time unit conversion", () => {
      const micro = systemTime(Type.atom("microsecond")).value;
      const nano = systemTime(Type.atom("nanosecond")).value;

      // Allow small timing drift between calls
      assert.isTrue(nano >= micro * 999n);
      assert.isTrue(nano <= micro * 1001n + 1000n);
    });

    it("raises ArgumentError when argument is not atom or integer", () => {
      assertBoxedError(
        () => systemTime(Type.float(1.0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError when atom argument is not a valid time unit", () => {
      assertBoxedError(
        () => systemTime(Type.atom("invalid")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError when integer argument is 0", () => {
      assertBoxedError(
        () => systemTime(Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });

    it("raises ArgumentError when integer argument is negative", () => {
      assertBoxedError(
        () => systemTime(Type.integer(-1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    });
  });

  describe("type/0", () => {
    const type = Erlang_Os["type/0"];

    it("returns OS family and OS name", () => {
      const result = type();

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.atom("unix"), Type.atom("web")]),
      );
    });
  });
});

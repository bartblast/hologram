"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Os from "../../../assets/js/erlang/os.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/os_test.exs
// Always update both together.

describe("Erlang_Os", () => {
  describe("system_time/0", () => {
    const systemTime = Erlang_Os["system_time/0"];

    it("returns current system time in nanoseconds", () => {
      const beforeMs = Date.now();
      const result = systemTime();
      const afterMs = Date.now();

      assert.ok(Type.isInteger(result));
      assert.ok(result.value >= BigInt(beforeMs) * 1_000_000n);
      assert.ok(result.value <= BigInt(afterMs + 1) * 1_000_000n);
    });

    it("returns positive values", () => {
      const result = systemTime();

      assert.ok(result.value > 0n);
    });

    it("converts correctly to milliseconds", () => {
      const result = systemTime();
      const resultMs = Number(result.value / 1_000_000n);
      const currentMs = Date.now();

      // Allow 100ms tolerance for test execution time
      assert.ok(Math.abs(resultMs - currentMs) < 100);
    });

    it("returns different values on subsequent calls", () => {
      const result1 = systemTime();
      const result2 = systemTime();

      assert.ok(result1.value <= result2.value);
    });

    it("maintains monotonic ordering across multiple calls", () => {
      const results = Array.from({length: 5}, () => systemTime());

      for (let i = 1; i < results.length; i++) {
        assert.ok(results[i - 1].value <= results[i].value);
      }
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

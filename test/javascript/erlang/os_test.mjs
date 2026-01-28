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

    it("returns current system time in native time unit (nanoseconds)", () => {
      const beforeMs = Date.now();
      const result = systemTime();
      const afterMs = Date.now();

      assert.isTrue(Type.isInteger(result));
      assert.isAtLeast(result.value, BigInt(beforeMs) * 1_000_000n);
      assert.isAtMost(result.value, BigInt(afterMs + 1) * 1_000_000n);
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

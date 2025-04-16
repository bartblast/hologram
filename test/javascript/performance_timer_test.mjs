"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import PerformanceTimer from "../../assets/js/performance_timer.mjs";

defineGlobalErlangAndElixirModules();

describe("PerformanceTimer", () => {
  describe("diff()", () => {
    it("returns time in microseconds when difference is less than 1 ms", () => {
      // Create a mock timestamp very close to now to ensure sub-millisecond difference
      const startTime = performance.now() - 0.5;

      const result = PerformanceTimer.diff(startTime);
      assert.match(result, /^\d+ μs$/);

      const value = parseInt(result);
      assert.isAtLeast(value, 500); // Allow for some overhead
      assert.isBelow(value, 1000); // Should still be less than 1ms
    });

    it("returns time in milliseconds when difference is 1 ms or greater", () => {
      const startTime = performance.now() - 1;
      const result = PerformanceTimer.diff(startTime);

      assert.equal(result, "1 ms");
    });
  });

  describe("start()", () => {
    it("returns current timestamp", () => {
      const result = PerformanceTimer.start();

      assert.isNumber(result);
      assert.isAtMost(performance.now() - result, 1);
    });
  });
});

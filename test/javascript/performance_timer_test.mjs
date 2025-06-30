"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import PerformanceTimer from "../../assets/js/performance_timer.mjs";

defineGlobalErlangAndElixirModules();

describe("PerformanceTimer", () => {
  let performanceNowStub;

  beforeEach(() => {
    performanceNowStub = sinon.stub(performance, "now");
    performanceNowStub.onCall(0).returns(1_000); // start time
  });

  afterEach(() => {
    sinon.restore();
  });

  describe("diff()", () => {
    it("returns time in microseconds when difference is less than 1 ms", () => {
      performanceNowStub.onCall(1).returns(1_000.5); // end time

      const startTime = PerformanceTimer.start();
      const result = PerformanceTimer.diff(startTime);

      assert.equal(result, "500 μs");
    });

    it("returns time in milliseconds when difference is 1 ms or greater", () => {
      performanceNowStub.onCall(1).returns(1_002.7); // end time

      const startTime = PerformanceTimer.start();
      const result = PerformanceTimer.diff(startTime);

      assert.equal(result, "3 ms");
    });
  });

  describe("start()", () => {
    it("returns current timestamp", () => {
      const result = PerformanceTimer.start();

      assert.isNumber(result);
      assert.equal(result, 1_000);
    });
  });
});

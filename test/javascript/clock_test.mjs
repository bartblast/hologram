"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import Clock from "../../assets/js/clock.mjs";

describe("Clock", () => {
  // A wall clock frozen at a known millisecond, so every expectation below is that millisecond's
  // stamp rather than whatever the machine's clock happens to read.
  const nowMs = 1_756_100_000_123;

  let timers;

  beforeEach(() => {
    Clock.reset();
    timers = sinon.useFakeTimers(nowMs);
  });

  afterEach(() => {
    timers.restore();
  });

  describe("observe()", () => {
    it("lifts the clock above a stamp ahead of the wall clock", () => {
      Clock.observe(nowMs * 1024 + 5000);

      assert.equal(Clock.stamp(), nowMs * 1024 + 5001);
    });

    it("leaves the clock alone for a stamp behind it", () => {
      Clock.observe(nowMs * 1024 - 5000);

      assert.equal(Clock.stamp(), nowMs * 1024);
    });

    it("leaves the clock alone for a stamp it has already authored", () => {
      const stamp = Clock.stamp();

      Clock.observe(stamp);

      assert.equal(Clock.stamp(), stamp + 1);
    });
  });

  describe("reset()", () => {
    it("forgets what the clock authored", () => {
      Clock.stamp();
      Clock.stamp();
      Clock.reset();

      assert.equal(Clock.stamp(), nowMs * 1024);
    });

    it("forgets what the clock observed", () => {
      Clock.observe(nowMs * 1024 + 5000);
      Clock.reset();

      assert.equal(Clock.stamp(), nowMs * 1024);
    });
  });

  describe("wallClockMs()", () => {
    it("answers the millisecond a stamp was taken at", () => {
      assert.equal(Clock.wallClockMs(Clock.stamp()), nowMs);
    });

    it("answers the same millisecond for every stamp taken within it", () => {
      Clock.stamp();

      assert.equal(Clock.wallClockMs(Clock.stamp()), nowMs);
    });
  });

  describe("stamp()", () => {
    it("increases strictly within one millisecond", () => {
      assert.equal(Clock.stamp(), nowMs * 1024);
      assert.equal(Clock.stamp(), nowMs * 1024 + 1);
      assert.equal(Clock.stamp(), nowMs * 1024 + 2);
    });

    it("stays under the largest integer JavaScript holds exactly", () => {
      assert.isBelow(Clock.stamp(), Number.MAX_SAFE_INTEGER);
    });

    it("takes the wall clock as its upper bits", () => {
      assert.equal(Clock.stamp(), nowMs * 1024);
    });

    it("takes the wall clock forward with it", () => {
      Clock.stamp();
      timers.tick(1);

      assert.equal(Clock.stamp(), (nowMs + 1) * 1024);
    });
  });
});

"use strict";

import {assert} from "./support/helpers.mjs";

import Calendar from "../../assets/js/calendar.mjs";

// The rules this module mirrors are Calendar.ISO's, so every expectation below is what the Elixir
// function answers for the same arguments - probed, not reasoned. Its two callers pin the rules
// through their own paths as well; this file pins the module's own contract, including the half
// no caller can reach.
describe("Calendar", () => {
  describe("validDate()", () => {
    it("accepts a real date", () => {
      assert.isTrue(Calendar.validDate(2026, 7, 17));
    });

    it("refuses a month outside 1..12", () => {
      assert.isFalse(Calendar.validDate(2026, 0, 1));
      assert.isFalse(Calendar.validDate(2026, 13, 1));
    });

    it("refuses a day outside the month's length", () => {
      assert.isFalse(Calendar.validDate(2026, 1, 0));
      assert.isFalse(Calendar.validDate(2026, 1, 32));
      assert.isTrue(Calendar.validDate(2026, 1, 31));
    });

    it("knows which months have thirty days", () => {
      for (const month of [4, 6, 9, 11]) {
        assert.isTrue(Calendar.validDate(2026, month, 30), `month ${month}`);
        assert.isFalse(Calendar.validDate(2026, month, 31), `month ${month}`);
      }
    });

    // leap_year?/1 is `rem(year, 4) === 0 and (rem(year, 100) !== 0 or rem(year, 400) === 0)`.
    // A year divisible by four is the easy half; the century rule is the one every earlier test
    // in this suite happened to miss, since 2024 and 2026 never reach it.
    it("applies the proleptic Gregorian leap rule, century exception included", () => {
      assert.isTrue(Calendar.validDate(2024, 2, 29));
      assert.isFalse(Calendar.validDate(2026, 2, 29));
      assert.isFalse(Calendar.validDate(2024, 2, 30));

      assert.isTrue(Calendar.validDate(2000, 2, 29), "divisible by 400");
      assert.isFalse(
        Calendar.validDate(1900, 2, 29),
        "divisible by 100, not by 400",
      );
      assert.isFalse(
        Calendar.validDate(2100, 2, 29),
        "divisible by 100, not by 400",
      );
    });

    // is_year/1 asks only that the year is an integer, so year zero and years before it are dates.
    it("leaves the year unconstrained", () => {
      assert.isTrue(Calendar.validDate(0, 1, 1));
      assert.isTrue(Calendar.validDate(-1, 12, 31));
      assert.isTrue(
        Calendar.validDate(-4, 2, 29),
        "-4 is a leap year in the proleptic calendar",
      );
    });

    it("refuses a fractional component", () => {
      assert.isFalse(Calendar.validDate(2026.5, 7, 17));
      assert.isFalse(Calendar.validDate(2026, 7.5, 17));
      assert.isFalse(Calendar.validDate(2026, 7, 17.5));
    });
  });

  describe("storableDate()", () => {
    it("accepts the first and the last day a date column holds", () => {
      assert.isTrue(Calendar.storableDate(-4713n, 11n, 24n));
      assert.isTrue(Calendar.storableDate(5874897n, 12n, 31n));
    });

    it("refuses the day before the first and the day after the last", () => {
      assert.isFalse(Calendar.storableDate(-4713n, 11n, 23n));
      assert.isFalse(Calendar.storableDate(5874898n, 1n, 1n));
    });

    it("refuses a year a Number would round", () => {
      assert.isFalse(Calendar.storableDate(10n ** 30n, 1n, 1n));
      assert.isFalse(Calendar.storableDate(-(10n ** 30n), 1n, 1n));
    });
  });

  describe("storableDateTime()", () => {
    it("accepts the first and the last second", () => {
      assert.isTrue(
        Calendar.storableDateTime(-4713n, 11n, 24n, 0n, 0n, 0n, 0n),
      );

      assert.isTrue(
        Calendar.storableDateTime(9999n, 12n, 31n, 23n, 59n, 59n, 0n),
      );
    });

    it("refuses the second before the first and after the last", () => {
      assert.isFalse(
        Calendar.storableDateTime(-4713n, 11n, 23n, 23n, 59n, 59n, 0n),
      );

      assert.isFalse(Calendar.storableDateTime(10000n, 1n, 1n, 0n, 0n, 0n, 0n));
    });

    it("judges the instant the offset gives", () => {
      assert.isTrue(
        Calendar.storableDateTime(10000n, 1n, 1n, 0n, 0n, 0n, 3600n),
      );

      assert.isFalse(
        Calendar.storableDateTime(9999n, 12n, 31n, 23n, 59n, 59n, -1n),
      );

      assert.isTrue(
        Calendar.storableDateTime(-4713n, 11n, 23n, 23n, 0n, 0n, -3600n),
      );

      assert.isFalse(
        Calendar.storableDateTime(-4713n, 11n, 24n, 0n, 0n, 0n, 1n),
      );
    });

    // Each date with the offset that lands it exactly on the last storable second, so a day
    // miscounted anywhere before it moves the answer. The Unix seconds are Elixir's.
    it("counts leap days, before and after year 0", () => {
      const lastSecond = 253402300799n;

      for (const [year, month, day, unixSeconds] of [
        [2000n, 2n, 29n, 951782400n],
        [2000n, 3n, 1n, 951868800n],
        [-4n, 2n, 29n, -62288352000n],
        [-4n, 3n, 1n, -62288265600n],
      ]) {
        const offset = unixSeconds - lastSecond;

        assert.isTrue(
          Calendar.storableDateTime(year, month, day, 0n, 0n, 0n, offset),
        );

        assert.isFalse(
          Calendar.storableDateTime(year, month, day, 0n, 0n, 0n, offset - 1n),
        );
      }
    });

    it("refuses a year a JavaScript Date can't reach", () => {
      assert.isFalse(
        Calendar.storableDateTime(300000n, 1n, 1n, 0n, 0n, 0n, 0n),
      );
    });

    it("takes the first and last whole year a JavaScript Date holds", () => {
      assert.isTrue(
        Calendar.storableDateTime(
          -271820n,
          1n,
          1n,
          0n,
          0n,
          0n,
          -8893380182399n,
        ),
      );

      assert.isTrue(
        Calendar.storableDateTime(
          275759n,
          12n,
          31n,
          23n,
          59n,
          59n,
          8850844684799n,
        ),
      );
    });

    it("refuses the years just past those, with offsets landing in range", () => {
      assert.isFalse(
        Calendar.storableDateTime(
          -271821n,
          12n,
          31n,
          0n,
          0n,
          0n,
          -8429111164800n,
        ),
      );

      assert.isFalse(
        Calendar.storableDateTime(275760n, 1n, 1n, 0n, 0n, 0n, 8850844684800n),
      );
    });

    it("refuses such a year even when its offset brings the instant back in range", () => {
      assert.isFalse(
        Calendar.storableDateTime(300000n, 1n, 1n, 0n, 0n, 0n, 9400000000000n),
      );
    });
  });

  describe("validTime()", () => {
    it("accepts the first and the last instant of the day", () => {
      assert.isTrue(Calendar.validTime(0, 0, 0, 0, 0));
      assert.isTrue(Calendar.validTime(23, 59, 59, 999999, 6));
    });

    it("refuses a clock field outside its range", () => {
      assert.isFalse(Calendar.validTime(24, 0, 0, 0, 0));
      assert.isFalse(Calendar.validTime(-1, 0, 0, 0, 0));
      assert.isFalse(Calendar.validTime(0, 60, 0, 0, 0));
      assert.isFalse(Calendar.validTime(0, 0, 60, 0, 0));
    });

    // is_microsecond judges the precision beside the amount.
    it("refuses a microsecond amount or precision outside its range", () => {
      assert.isFalse(Calendar.validTime(0, 0, 0, 1000000, 6));
      assert.isFalse(Calendar.validTime(0, 0, 0, -1, 6));
      assert.isFalse(Calendar.validTime(0, 0, 0, 0, 7));
      assert.isFalse(Calendar.validTime(0, 0, 0, 0, -1));
    });

    it("refuses a fractional component", () => {
      assert.isFalse(Calendar.validTime(11.5, 0, 0, 0, 0));
      assert.isFalse(Calendar.validTime(11, 0.5, 0, 0, 0));
      assert.isFalse(Calendar.validTime(11, 0, 0.5, 0, 0));
      assert.isFalse(Calendar.validTime(11, 0, 0, 0.5, 6));
      assert.isFalse(Calendar.validTime(11, 0, 0, 0, 6.5));
    });

    // What a JavaScript number cannot tell apart: the boxed-term check in the entity validator is
    // the half that refuses a whole-valued FLOAT, and this module knowingly does not.
    it("cannot tell a whole-valued float from an integer, by construction", () => {
      assert.isTrue(Calendar.validTime(11.0, 0, 0, 0, 0));
    });
  });
});

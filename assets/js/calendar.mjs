"use strict";

// Calendar.ISO's validity rules, hand-written rather than called. The transpiled Calendar.ISO is
// not dependable here: measured against a built features app, valid_date?/3 lands in 1 of 207 PAGE
// bundles - whichever page's own code happens to reach it - and in no runtime bundle, while
// valid_time?/4 lands in none at all. Both readers of this module ship in the runtime bundle, so a
// call to the transpiled original would work on one page and throw on every other.
//
// Two readers, which is why this is its own module rather than a private half of either: the
// hand-ported Hologram.Entity validator, which refuses a value a template or an action hands in,
// and Model's box helpers, which refuse a value the wire hands back. model.mjs is a base module
// that entity.mjs imports, so the helpers cannot live in entity.mjs without inverting that.
//
// Split the way Elixir splits it - validDate against valid_date?/3, daysInMonth against
// days_in_month/2, leapYear against leap_year?/1 - so a later divergence shows up in the half that
// moved.
//
// Both Elixir functions are defined for integers only, and each helper refuses a fractional
// component for the same reason. That is as far as a JavaScript number can carry the rule: 6.0 and
// 6 are one value here, so a whole-valued float passes this half and is refused only where the
// boxed term is still in hand, in the entity validator's Type.isInteger check. Both halves together
// are the guard; neither alone is.
export default class Calendar {
  // valid_date?/3 is `is_month(month) and day in 1..days_in_month(year, month)`. The year is
  // unconstrained: is_year/1 asks only that it is an integer.
  static validDate(year, month, day) {
    return (
      Calendar.#integers(year, month, day) &&
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= Calendar.#daysInMonth(year, month)
    );
  }

  // valid_time?/4 is `is_hour and is_minute and is_second and is_microsecond(amount, precision)`,
  // and is_microsecond is `microsecond in 0..999_999 and precision in 0..6` - so the PRECISION is
  // judged beside the amount, which a check over the clock fields alone would miss.
  static validTime(hour, minute, second, microsecond, precision) {
    return (
      Calendar.#integers(hour, minute, second, microsecond, precision) &&
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59 &&
      second >= 0 &&
      second <= 59 &&
      microsecond >= 0 &&
      microsecond <= 999999 &&
      precision >= 0 &&
      precision <= 6
    );
  }

  static #integers(...values) {
    return values.every(Number.isInteger);
  }

  static #daysInMonth(year, month) {
    if (month === 2) {
      return Calendar.#leapYear(year) ? 29 : 28;
    }

    return [4, 6, 9, 11].includes(month) ? 30 : 31;
  }

  static #leapYear(year) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  }
}

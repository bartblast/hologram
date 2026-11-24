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

  // Hologram.DB.Codec.storable_date?/1: the days a date column holds. The fields are BigInts, as a
  // boxed integer holds them, because a struct can carry a year a Number would round.
  static storableDate(year, month, day) {
    const date = [year, month, day];

    return (
      Calendar.#compareFields(date, Calendar.#FIRST_COLUMN_DAY) >= 0 &&
      Calendar.#compareFields(date, Calendar.#LAST_COLUMN_DAY) <= 0
    );
  }

  // Hologram.DB.Codec.storable_datetime?/1: the instants a datetime can be stored at, judged after
  // the offset moves it. Counted in whole seconds, since the first bound starts one and the last
  // ends one. Worked out by hand in BigInts, because a JavaScript Date stops at year 275760 and
  // would answer an invalid date for a value this has to refuse.
  //
  // Stricter than the server in one way: a wall clock a Date can't hold is refused even when its
  // offset brings the instant back in range, since a Date is what spells a datetime for the wire.
  static storableDateTime(year, month, day, hour, minute, second, offset) {
    if (
      year < Calendar.#FIRST_DATE_OBJECT_YEAR ||
      year > Calendar.#LAST_DATE_OBJECT_YEAR
    ) {
      return false;
    }

    const seconds =
      Calendar.#daysFromEpoch(year, month, day) * 86400n +
      hour * 3600n +
      minute * 60n +
      second -
      offset;

    return (
      seconds >= Calendar.#FIRST_STORABLE_SECOND &&
      seconds <= Calendar.#LAST_STORABLE_SECOND
    );
  }

  // The whole years a JavaScript Date can hold.
  static #FIRST_DATE_OBJECT_YEAR = -271820n;

  static #LAST_DATE_OBJECT_YEAR = 275759n;

  static #FIRST_COLUMN_DAY = [-4713n, 11n, 24n];

  static #LAST_COLUMN_DAY = [5874897n, 12n, 31n];

  // -4713-11-24T00:00:00Z and 9999-12-31T23:59:59Z as Unix seconds.
  static #FIRST_STORABLE_SECOND = -210866803200n;

  static #LAST_STORABLE_SECOND = 253402300799n;

  static #compareFields(left, right) {
    for (const [index, field] of left.entries()) {
      if (field !== right[index]) {
        return field < right[index] ? -1 : 1;
      }
    }

    return 0;
  }

  // The days from 1970-01-01 to the given proleptic Gregorian date, counted over 400-year eras
  // from a year that starts in March, which puts the leap day last.
  static #daysFromEpoch(year, month, day) {
    const shiftedYear = month <= 2n ? year - 1n : year;
    const era = Calendar.#floorDivide(shiftedYear, 400n);
    const yearOfEra = shiftedYear - era * 400n;
    const shiftedMonth = month > 2n ? month - 3n : month + 9n;
    const dayOfYear = (153n * shiftedMonth + 2n) / 5n + day - 1n;

    const dayOfEra =
      yearOfEra * 365n + yearOfEra / 4n - yearOfEra / 100n + dayOfYear;

    return era * 146097n + dayOfEra - 719468n;
  }

  // BigInt division truncates toward zero, and a year before 0 needs it to round down.
  static #floorDivide(dividend, divisor) {
    const quotient = dividend / divisor;

    return dividend % divisor < 0n ? quotient - 1n : quotient;
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

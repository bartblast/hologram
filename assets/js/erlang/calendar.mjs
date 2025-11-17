"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Helper to check if a year is a leap year
function isLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || (year % 400 === 0);
}

// Days in each month
function daysInMonth(year, month) {
  const days = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return days[month - 1];
}

// Calculate days since year 0
function dateToDays(year, month, day) {
  let days = day;

  // Add days for complete years
  for (let y = 0; y < year; y++) {
    days += isLeapYear(y) ? 366 : 365;
  }

  // Add days for complete months in current year
  for (let m = 1; m < month; m++) {
    days += daysInMonth(year, m);
  }

  return days;
}

// Convert days since year 0 to date
function daysToDate(totalDays) {
  let year = 0;
  let days = totalDays;

  // Find the year
  while (true) {
    const daysInYear = isLeapYear(year) ? 366 : 365;
    if (days <= daysInYear) {
      break;
    }
    days -= daysInYear;
    year++;
  }

  // Find the month
  let month = 1;
  while (month <= 12) {
    const daysInCurrentMonth = daysInMonth(year, month);
    if (days <= daysInCurrentMonth) {
      break;
    }
    days -= daysInCurrentMonth;
    month++;
  }

  return {year, month, day: days};
}

const Erlang_Calendar = {
  // Start universal_time/0
  "universal_time/0": () => {
    const now = new Date();

    // Return {{Year, Month, Day}, {Hour, Minute, Second}}
    const date = Type.tuple([
      Type.integer(now.getUTCFullYear()),
      Type.integer(now.getUTCMonth() + 1), // JavaScript months are 0-indexed
      Type.integer(now.getUTCDate()),
    ]);

    const time = Type.tuple([
      Type.integer(now.getUTCHours()),
      Type.integer(now.getUTCMinutes()),
      Type.integer(now.getUTCSeconds()),
    ]);

    return Type.tuple([date, time]);
  },
  // End universal_time/0
  // Deps: []

  // Start local_time/0
  "local_time/0": () => {
    const now = new Date();

    // Return {{Year, Month, Day}, {Hour, Minute, Second}}
    const date = Type.tuple([
      Type.integer(now.getFullYear()),
      Type.integer(now.getMonth() + 1), // JavaScript months are 0-indexed
      Type.integer(now.getDate()),
    ]);

    const time = Type.tuple([
      Type.integer(now.getHours()),
      Type.integer(now.getMinutes()),
      Type.integer(now.getSeconds()),
    ]);

    return Type.tuple([date, time]);
  },
  // End local_time/0
  // Deps: []

  // Start now_to_universal_time/1
  "now_to_universal_time/1": (now) => {
    if (!Type.isTuple(now) || now.data.length !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid now() tuple"),
      );
    }

    // now() returns {MegaSecs, Secs, MicroSecs}
    const megaSecs = Number(now.data[0].value);
    const secs = Number(now.data[1].value);

    // Convert to milliseconds since epoch
    const totalSecs = megaSecs * 1000000 + secs;
    const date = new Date(totalSecs * 1000);

    // Return {{Year, Month, Day}, {Hour, Minute, Second}}
    const dateTriple = Type.tuple([
      Type.integer(date.getUTCFullYear()),
      Type.integer(date.getUTCMonth() + 1),
      Type.integer(date.getUTCDate()),
    ]);

    const timeTriple = Type.tuple([
      Type.integer(date.getUTCHours()),
      Type.integer(date.getUTCMinutes()),
      Type.integer(date.getUTCSeconds()),
    ]);

    return Type.tuple([dateTriple, timeTriple]);
  },
  // End now_to_universal_time/1
  // Deps: []

  // Start datetime_to_gregorian_seconds/1
  "datetime_to_gregorian_seconds/1": (datetime) => {
    if (!Type.isTuple(datetime) || datetime.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid datetime"),
      );
    }

    const date = datetime.data[0];
    const time = datetime.data[1];

    if (!Type.isTuple(date) || date.data.length !== 3 ||
        !Type.isTuple(time) || time.data.length !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid datetime"),
      );
    }

    const year = Number(date.data[0].value);
    const month = Number(date.data[1].value);
    const day = Number(date.data[2].value);

    const hour = Number(time.data[0].value);
    const minute = Number(time.data[1].value);
    const second = Number(time.data[2].value);

    // Calculate total days since year 0
    const totalDays = dateToDays(year, month, day);

    // Calculate total seconds
    const totalSeconds = totalDays * 86400 + hour * 3600 + minute * 60 + second;

    return Type.integer(totalSeconds);
  },
  // End datetime_to_gregorian_seconds/1
  // Deps: []

  // Start gregorian_seconds_to_datetime/1
  "gregorian_seconds_to_datetime/1": (seconds) => {
    if (!Type.isInteger(seconds)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    const totalSeconds = Number(seconds.value);

    // Calculate days and remaining seconds
    const totalDays = Math.floor(totalSeconds / 86400);
    const remainingSeconds = totalSeconds % 86400;

    // Calculate time components
    const hour = Math.floor(remainingSeconds / 3600);
    const minute = Math.floor((remainingSeconds % 3600) / 60);
    const second = remainingSeconds % 60;

    // Calculate date components
    const {year, month, day} = daysToDate(totalDays);

    const date = Type.tuple([
      Type.integer(year),
      Type.integer(month),
      Type.integer(day),
    ]);

    const time = Type.tuple([
      Type.integer(hour),
      Type.integer(minute),
      Type.integer(second),
    ]);

    return Type.tuple([date, time]);
  },
  // End gregorian_seconds_to_datetime/1
  // Deps: []
};

export default Erlang_Calendar;

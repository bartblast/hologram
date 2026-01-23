"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Os = {
  // Start system_time/0
  "system_time/0": () => {
    // Returns current system time in native time unit (nanoseconds)
    // In Erlang, system_time/0 returns a large integer representing nanoseconds since epoch
    // TODO: Once PR #590 (monotonic_time) is merged, review time source patterns for consistency
    const timeNs = BigInt(Date.now()) * BigInt(1000000);
    return Type.integer(timeNs);
  },
  // End system_time/0
  // Deps: []

  // Start system_time/1
  "system_time/1": (unit) => {
    // Get current time source
    // Prefer performance API for perf_counter, otherwise use Date.now()
    // Similar to Erlang's system_time which returns a large integer
    // TODO: Once PR #590 (monotonic_time) is merged, review time source patterns for consistency
    let timeNs;

    // Check if this is a perf_counter request and performance API is available
    const isPerformanceRequest =
      Type.isAtom(unit) &&
      unit.value === "perf_counter" &&
      typeof performance !== "undefined" &&
      performance.timeOrigin &&
      performance.now;

    if (isPerformanceRequest) {
      // For perf_counter, compute epoch-based timestamp using performance API
      // performance.timeOrigin gives the epoch time (milliseconds), performance.now() gives
      // high-resolution elapsed time since page load. Together they provide an accurate
      // epoch-based high-resolution timestamp.
      const epochTimeMs =
        BigInt(Math.floor(performance.timeOrigin)) +
        BigInt(Math.floor(performance.now()));
      timeNs = epochTimeMs * BigInt(1000000);
    } else {
      // For all other units, use Date.now() as the time source
      timeNs = BigInt(Date.now()) * BigInt(1000000);
    }

    // Convert unit parameter to a numeric value (parts per second)
    // TODO: Once PR #603 (convert_time_unit/3) is merged, consider refactoring unit handling
    //       to use the centralized convert_time_unit/3 function for consistency
    let unitPps;

    if (Type.isAtom(unit)) {
      switch (unit.value) {
        case "second":
          unitPps = BigInt(1);
          break;
        case "millisecond":
          unitPps = BigInt(1000);
          break;
        case "microsecond":
          unitPps = BigInt(1000000);
          break;
        case "nanosecond":
          unitPps = BigInt(1000000000);
          break;
        case "native":
          unitPps = BigInt(1000000000); // Native unit is nanoseconds in both Erlang and here
          break;
        case "perf_counter":
          unitPps = BigInt(1000000000); // perf_counter is nanoseconds
          break;
        default:
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
          );
      }
    } else if (Type.isInteger(unit)) {
      if (unit.value <= 0n) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
        );
      }

      unitPps = BigInt(unit.value);
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "invalid time unit"),
      );
    }

    // Convert from nanoseconds to the requested unit
    // timeNs is in nanoseconds, which is 1000000000 pps
    // To convert to target unit: (timeNs / 1000000000) * unitPps
    // TODO: Once PR #603 (convert_time_unit/3) is merged, this conversion logic could be
    //       replaced with: Erlang['convert_time_unit/3'](timeNs, Type.integer(1000000000n), unit)
    const convertedTime = (timeNs * unitPps) / BigInt(1000000000);

    return Type.integer(convertedTime);
  },
  // End system_time/1
  // Deps: []
  // Future deps: [:erlang.convert_time_unit/3] (after PR #603 merge)
};

export default Erlang_Os;

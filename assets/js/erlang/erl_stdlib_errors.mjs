"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Erl_Stdlib_Errors = {
  // Start format_error/2
  "format_error/2": (reason, stacktrace) => {
    const isFourTupleTopFrame =
      Type.isList(stacktrace) &&
      stacktrace.data.length > 0 &&
      Type.isTuple(stacktrace.data[0]) &&
      stacktrace.data[0].data.length === 4;

    if (!isFourTupleTopFrame) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_error/2",
          [reason, stacktrace],
        ),
      );
    }

    const frameModule = stacktrace.data[0].data[0];

    // TODO: port the per-module formatters from :erl_stdlib_errors
    // (format_maps_error, format_binary_error, ...) as the stdlib ports
    // migrate their raise sites to bare reasons with error_info.
    let fragments;

    switch (frameModule.value) {
      default:
        fragments = [];
    }

    // Mirrors format_error_map/3: fragments map to argument positions in
    // order, "" entries skip their position, and {general: text} entries
    // land under the :general key instead of consuming a position.
    const entries = [];
    let argumentNumber = 1;

    for (const fragment of fragments) {
      if (fragment === "") {
        ++argumentNumber;
        continue;
      }

      if (typeof fragment === "object") {
        entries.push([Type.atom("general"), Type.bitstring(fragment.general)]);
        continue;
      }

      entries.push([Type.integer(argumentNumber), Type.bitstring(fragment)]);

      ++argumentNumber;
    }

    return Type.map(entries);
  },
  // End format_error/2
  // Deps: []
};

export default Erlang_Erl_Stdlib_Errors;

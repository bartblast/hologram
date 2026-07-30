"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Erl_Kernel_Errors = {
  // Mirrors OTP's private expand_error/1, returning boxed chardata. Every
  // fragment text is colocated here, and fragments without an entry are
  // literal texts that pass through unchanged, like OTP's
  // expand_error(Other) -> Other fallback.
  // Start _expand_error/1
  "_expand_error/1": (fragment) => {
    const texts = {
      invalid_time_unit: "invalid time unit",
    };

    return Type.bitstring(texts[fragment] ?? fragment);
  },
  // End _expand_error/1
  // Deps: []

  // Mirrors OTP's private format_error_map/3. Fragments map to argument
  // positions in order starting at the given number, and "" entries skip
  // their position. Entries accumulate into the given boxed map.
  // Start _format_error_map/3
  "_format_error_map/3": (fragments, argumentNumber, map) => {
    const result = Type.cloneMap(map);
    let currentArgumentNumber = argumentNumber;

    for (const fragment of fragments) {
      if (fragment === "") {
        ++currentArgumentNumber;
        continue;
      }

      const expand = Erlang_Erl_Kernel_Errors["_expand_error/1"];

      const key = Type.integer(currentArgumentNumber);
      result.data[Type.encodeMapKey(key)] = [key, expand(fragment)];

      ++currentArgumentNumber;
    }

    return result;
  },
  // End _format_error_map/3
  // Deps: [:erl_kernel_errors._expand_error/1]

  // Mirrors OTP's private format_os_error/3. Clauses for functions whose
  // client ports don't raise with an erl_kernel_errors error_info frame
  // are omitted - they fall through to the empty fragment list, like OTP's
  // catch-all clause, so their reasons derive the plain "argument error"
  // text.
  // Start _format_os_error/3
  "_format_os_error/3": (fun, argsOrArity, _cause) => {
    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;

    if (fun.value === "system_time" && args?.length === 1) {
      return ["invalid_time_unit"];
    }

    return [];
  },
  // End _format_os_error/3
  // Deps: []

  // Start format_error/2
  "format_error/2": (reason, stacktrace) => {
    const isFourTupleTopFrame =
      Type.isList(stacktrace) &&
      stacktrace.data.length > 0 &&
      Type.isTuple(stacktrace.data[0]) &&
      stacktrace.data[0].data.length === 4;

    if (!isFourTupleTopFrame) {
      Interpreter.raiseFunctionClauseError(
        "erl_kernel_errors",
        "format_error",
        2,
        [reason, stacktrace],
      );
    }

    const frameModule = stacktrace.data[0].data[0];
    const frameFun = stacktrace.data[0].data[1];
    const frameArgsOrArity = stacktrace.data[0].data[2];
    const frameLocation = stacktrace.data[0].data[3];

    // Mirrors OTP's cause lookup: the location's error_info map may carry a
    // cause entry that refines the formatter's diagnosis, defaulting to
    // :none.
    let cause = Type.atom("none");

    if (Type.isList(frameLocation)) {
      for (const entry of frameLocation.data) {
        if (
          Type.isTuple(entry) &&
          entry.data.length === 2 &&
          Type.isAtom(entry.data[0]) &&
          entry.data[0].value === "error_info" &&
          Type.isMap(entry.data[1])
        ) {
          const causeEntry =
            entry.data[1].data[Type.encodeMapKey(Type.atom("cause"))];

          if (causeEntry !== undefined) {
            cause = causeEntry[1];
          }
        }
      }
    }

    let fragments = [];

    if (frameModule.value === "os") {
      fragments = Erlang_Erl_Kernel_Errors["_format_os_error/3"](
        frameFun,
        frameArgsOrArity,
        cause,
      );
    }

    return Erlang_Erl_Kernel_Errors["_format_error_map/3"](
      fragments,
      1,
      Type.map(),
    );
  },
  // End format_error/2
  // Deps: [:erl_kernel_errors._format_error_map/3, :erl_kernel_errors._format_os_error/3]
};

export default Erlang_Erl_Kernel_Errors;

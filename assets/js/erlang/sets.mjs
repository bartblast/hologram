"use strict";

import Erlang_Lists from "./lists.mjs";
import Erlang_Maps from "./maps.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Sets = {
  // Start _validate_opts/3
  "_validate_opts/3": (opts, source, args) => {
    if (!Type.isList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(source, args),
      );
    }

    const versionOpt = Erlang_Lists["keyfind/3"](
      Type.atom("version"),
      Type.integer(1),
      opts,
    );

    if (Type.isBoolean(versionOpt) && versionOpt.value === "false") {
      return;
    }

    const value = versionOpt.data[1];

    if (!Type.isInteger(value)) {
      return;
    }

    const version = Number(value.value);

    if (version === 2) {
      return;
    }

    if (version === 1) {
      throw new HologramInterpreterError(
        ":sets version 1 is not supported in Hologram, use [{:version, 2}] option",
      );
    }

    Interpreter.raiseCaseClauseError(value);
  },
  // End _validate_opts/3
  // Deps: [:lists.keyfind/3]

  // Start from_list/2
  "from_list/2": (list, opts) => {
    Erlang_Sets["_validate_opts/3"](opts, ":sets.from_list/2", [list, opts]);
    return Erlang_Maps["from_keys/2"](list, Type.list([]));
  },
  // End from_list/2
  // Deps: [:sets._validate_opts/3, :maps.from_keys/2]

  // Start new/1
  "new/1": (options) => {
    Erlang_Sets["_validate_opts/3"](options, ":sets.new/1", [options]);
    return Type.map();
  },
  // End new/1
  // Deps: [:sets._validate_opts/3]

  // Start to_list/1
  "to_list/1": (set) => {
    if (!Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.to_list/1", [set]),
      );
    }

    return Erlang_Maps["keys/1"](set);
  },
  // End to_list/1
  // Deps: [:maps.keys/1]
};

export default Erlang_Sets;

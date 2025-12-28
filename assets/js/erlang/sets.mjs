"use strict";

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
    const raiseFunctionClauseError = () => {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(source, args),
      );
    };

    if (!Type.isList(opts)) {
      raiseFunctionClauseError();
    }

    if (opts.data.length === 0) {
      return;
    }

    if (opts.data.length !== 1) {
      raiseFunctionClauseError();
    }

    const opt = opts.data[0];

    if (!Type.isTuple(opt) || opt.data.length !== 2) {
      raiseFunctionClauseError();
    }

    const [key, value] = opt.data;

    if (!Type.isAtom(key) || key.value !== "version") {
      raiseFunctionClauseError();
    }

    if (!Type.isInteger(value)) {
      raiseFunctionClauseError();
    }

    const version = Number(value.value);

    if (version !== 1 && version !== 2) {
      raiseFunctionClauseError();
    }

    if (version === 1) {
      throw new HologramInterpreterError(
        ":sets version 1 is not supported in Hologram, use [{:version, 2}] option",
      );
    }
  },
  // End _validate_opts/3
  // Deps: []

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

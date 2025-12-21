"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Sets = {
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

"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Rand = {
  // TODO: Erlang docs say that "state in the process dictionary" is used
  // Start uniform/0
  "uniform/0": () => {
    return Type.float(Math.random());
  },
  // End uniform/0
  // Deps: []

  // TODO: Erlang docs say that "state in the process dictionary" is used
  // Start uniform/1
  "uniform/1": (integer) => {
    if (
      !Type.isInteger(integer) ||
      Interpreter.compareTerms(integer, Type.integer(0)) < 1
    ) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :rand.uniform_s/2",
      );
    }

    // TODO: support integers outside Number range
    return Type.integer(Math.floor(Math.random() * Number(integer.value)) + 1);
  },
  // End uniform/1
  // Deps: []
};

export default Erlang_Rand;

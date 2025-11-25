"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Math = {
  // Start exp/1
  "exp/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    const value = Type.isInteger(number) ? Number(number.value) : number.value;

    return Type.float(Math.exp(value));
  },
  // End exp/1
  // Deps: []
};

export default Erlang_Math;

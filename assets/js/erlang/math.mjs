"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Math = {
  // Start ceil/1
  "ceil/1": (x) => {
    if (!Type.isFloat(x) && !Type.isInteger(x)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number")
      );
    }

    return Type.float(Math.ceil(x.value));
  },
  // End ceil/1
  // Deps: []
};

export default Erlang_Math;

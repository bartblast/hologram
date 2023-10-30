"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Lists = {
  // start reverse/1
  "reverse/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :lists.reverse/1",
      );
    }

    return Type.list(list.data.toReversed());
  },
  // end reverse/1
  // deps: []
};

export default Erlang_Lists;

"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Code = {
  // This function is simplified - it returns either {:module, MyModule} or {:error, :nofile}.
  // Start ensure_loaded/1
  "ensure_loaded/1": function (module) {
    if (!Type.isAtom(module)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":code.ensure_loaded/1",
          arguments,
        ),
      );
    }

    return typeof Interpreter.moduleRef(module) === "undefined"
      ? Type.tuple([Type.atom("error"), Type.atom("nofile")])
      : Type.tuple([Type.atom("module"), module]);
  },
  // End ensure_loaded/1
  // Deps: []
};

export default Erlang_Code;

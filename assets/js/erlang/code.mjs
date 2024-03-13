"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Code = {
  // start ensure_loaded/1
  // This function is simplified - it returns either {:module, MyModule} or {:error, :nofile}.
  "ensure_loaded/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :code.ensure_loaded/1",
      );
    }

    return typeof Interpreter.moduleRef(module) === "undefined"
      ? Type.tuple([Type.atom("error"), Type.atom("nofile")])
      : Type.tuple([Type.atom("module"), module]);
  },
  // end ensure_loaded/1
  // deps: []
};

export default Erlang_Code;
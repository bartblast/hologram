"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Module = {
  // Start compile/5
  "compile/5": (module, block, vars, env, callback) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // This is a compiler function that would normally compile Elixir module definitions
    // In the Hologram runtime (client-side), modules are pre-compiled
    // This function is simplified and mainly returns a success marker

    // If a callback is provided, call it
    if (Type.isAnonymousFunction(callback)) {
      Interpreter.callAnonymousFunction(callback, [module, env]);
    }

    // Return the module name wrapped in a tuple to indicate success
    return Type.tuple([Type.atom("module"), module]);
  },
  // End compile/5
  // Deps: []
};

export default Erlang_Elixir_Module;

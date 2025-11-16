"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Erl_Eval = {
  // Start expr/2
  "expr/2": (expression, bindings) => {
    // erl_eval is for evaluating Erlang expressions at runtime
    // This is a compile-time feature that doesn't make sense in the browser context
    // Hologram pre-compiles everything to JavaScript

    Interpreter.raiseArgumentError(
      "erl_eval:expr/2 is not supported in client-side Hologram runtime. " +
      "Hologram pre-compiles all Elixir/Erlang code to JavaScript."
    );
  },
  // End expr/2
  // Deps: []
};

export default Erlang_Erl_Eval;

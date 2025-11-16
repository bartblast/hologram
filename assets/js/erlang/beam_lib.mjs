"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Beam_Lib = {
  // Start chunks/2
  "chunks/2": (beam, chunks) => {
    // beam_lib is for reading BEAM bytecode files
    // This is a compile-time tool that doesn't apply to the browser runtime
    // Hologram compiles to JavaScript, not BEAM

    Interpreter.raiseArgumentError(
      "beam_lib:chunks/2 is not supported in client-side Hologram runtime. " +
      "Hologram uses JavaScript, not BEAM bytecode."
    );
  },
  // End chunks/2
  // Deps: []
};

export default Erlang_Beam_Lib;

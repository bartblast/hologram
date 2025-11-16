"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Global store for command-line arguments (would be initialized at startup)
let commandLineArgs = {};

const Erlang_Init = {
  // Start get_argument/1
  "get_argument/1": (flag) => {
    if (!Type.isAtom(flag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    const flagName = flag.value;

    // Check if this flag exists in command-line arguments
    if (commandLineArgs[flagName]) {
      const values = commandLineArgs[flagName];
      // Return {ok, [[Value1], [Value2], ...]}
      const valueLists = values.map((v) => Type.list([v]));
      return Type.tuple([Type.atom("ok"), Type.list(valueLists)]);
    }

    // Flag not found
    return Type.atom("error");
  },
  // End get_argument/1
  // Deps: []

  // Helper function to set command-line arguments (not part of Erlang API)
  // This would be called during initialization
  "__setArguments__": (args) => {
    commandLineArgs = args;
  },
};

export default Erlang_Init;

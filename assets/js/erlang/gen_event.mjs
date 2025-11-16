"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Gen_Event = {
  // Start add_handler/3
  "add_handler/3": (eventManagerRef, handler, args) => {
    // gen_event is not supported client-side
    // Event handlers are server-side constructs
    Interpreter.raiseArgumentError(
      "gen_event:add_handler/3 is not supported in client-side Hologram runtime. " +
      "Use server-side Elixir code for event handling."
    );
  },
  // End add_handler/3
  // Deps: []

  // Start delete_handler/3
  "delete_handler/3": (eventManagerRef, handler, args) => {
    // gen_event is not supported client-side
    Interpreter.raiseArgumentError(
      "gen_event:delete_handler/3 is not supported in client-side Hologram runtime."
    );
  },
  // End delete_handler/3
  // Deps: []
};

export default Erlang_Gen_Event;

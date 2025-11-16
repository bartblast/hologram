"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Gen_Server = {
  // Start call/2
  "call/2": (serverRef, request) => {
    // In the client-side Hologram runtime, gen_server processes don't exist
    // This is a simplified implementation that would need to be connected to
    // the actual server-side process via WebSocket or similar mechanism

    // For now, raise an error indicating this is not supported client-side
    Interpreter.raiseArgumentError(
      "gen_server:call/2 is not supported in client-side Hologram runtime. " +
      "Use server-side Elixir code for process communication."
    );
  },
  // End call/2
  // Deps: []

  // Start call/3
  "call/3": (serverRef, request, timeout) => {
    // Similar to call/2, not supported client-side
    Interpreter.raiseArgumentError(
      "gen_server:call/3 is not supported in client-side Hologram runtime. " +
      "Use server-side Elixir code for process communication."
    );
  },
  // End call/3
  // Deps: []

  // Start cast/2
  "cast/2": (serverRef, request) => {
    // In the client-side runtime, we can't actually send messages to server processes
    // This would need to be implemented via WebSocket or HTTP requests in a real system

    // For now, return :ok to match the expected return value
    // In a full implementation, this would send a message to the server
    return Type.atom("ok");
  },
  // End cast/2
  // Deps: []

  // Start multi_call/4
  "multi_call/4": (nodes, name, request, timeout) => {
    // Multi-call is definitely not supported client-side
    Interpreter.raiseArgumentError(
      "gen_server:multi_call/4 is not supported in client-side Hologram runtime."
    );
  },
  // End multi_call/4
  // Deps: []
};

export default Erlang_Gen_Server;

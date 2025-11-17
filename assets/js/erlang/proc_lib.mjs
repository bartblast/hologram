"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Proc_Lib = {
  // Start spawn/1
  "spawn/1": (fun) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an anonymous function"),
      );
    }

    // In the client-side runtime, we don't have real process spawning
    // Return a dummy PID
    Interpreter.raiseArgumentError(
      "proc_lib:spawn/1 is not supported in client-side Hologram runtime. " +
      "Use server-side Elixir code for process management."
    );
  },
  // End spawn/1
  // Deps: []

  // Start spawn/3
  "spawn/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    Interpreter.raiseArgumentError(
      "proc_lib:spawn/3 is not supported in client-side Hologram runtime."
    );
  },
  // End spawn/3
  // Deps: []

  // Start spawn_link/1
  "spawn_link/1": (fun) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an anonymous function"),
      );
    }

    Interpreter.raiseArgumentError(
      "proc_lib:spawn_link/1 is not supported in client-side Hologram runtime."
    );
  },
  // End spawn_link/1
  // Deps: []

  // Start spawn_link/3
  "spawn_link/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    Interpreter.raiseArgumentError(
      "proc_lib:spawn_link/3 is not supported in client-side Hologram runtime."
    );
  },
  // End spawn_link/3
  // Deps: []
};

export default Erlang_Proc_Lib;

"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Supervisor = {
  // Start start_link/2
  "start_link/2": (module, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Supervisors are server-side OTP constructs
    Interpreter.raiseArgumentError(
      "supervisor:start_link/2 is not supported in client-side Hologram runtime. " +
      "Use server-side Elixir code for supervision trees."
    );
  },
  // End start_link/2
  // Deps: []

  // Start start_link/3
  "start_link/3": (name, module, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    Interpreter.raiseArgumentError(
      "supervisor:start_link/3 is not supported in client-side Hologram runtime."
    );
  },
  // End start_link/3
  // Deps: []

  // Start start_child/2
  "start_child/2": (supervisorRef, childSpec) => {
    // Supervisors are server-side OTP constructs
    Interpreter.raiseArgumentError(
      "supervisor:start_child/2 is not supported in client-side Hologram runtime."
    );
  },
  // End start_child/2
  // Deps: []

  // Start terminate_child/2
  "terminate_child/2": (supervisorRef, childId) => {
    Interpreter.raiseArgumentError(
      "supervisor:terminate_child/2 is not supported in client-side Hologram runtime."
    );
  },
  // End terminate_child/2
  // Deps: []

  // Start delete_child/2
  "delete_child/2": (supervisorRef, childId) => {
    Interpreter.raiseArgumentError(
      "supervisor:delete_child/2 is not supported in client-side Hologram runtime."
    );
  },
  // End delete_child/2
  // Deps: []

  // Start which_children/1
  "which_children/1": (supervisorRef) => {
    Interpreter.raiseArgumentError(
      "supervisor:which_children/1 is not supported in client-side Hologram runtime."
    );
  },
  // End which_children/1
  // Deps: []
};

export default Erlang_Supervisor;

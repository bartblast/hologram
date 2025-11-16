"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Global registry for overridable functions
const overridableRegistry = new Map();

const Erlang_Elixir_Overridable = {
  // Start record_overridable/4
  "record_overridable/4": (module, name, arity, kind) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(name)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isInteger(arity)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    if (!Type.isAtom(kind)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(4, "not an atom"),
      );
    }

    // Record this function as overridable
    const moduleKey = module.value;
    const funKey = `${name.value}/${arity.value}`;

    if (!overridableRegistry.has(moduleKey)) {
      overridableRegistry.set(moduleKey, new Map());
    }

    const moduleFuns = overridableRegistry.get(moduleKey);
    moduleFuns.set(funKey, {
      name: name,
      arity: arity,
      kind: kind,
      overridden: false,
    });

    // Return :ok
    return Type.atom("ok");
  },
  // End record_overridable/4
  // Deps: []

  // Helper function to check if a function is overridable (not part of Erlang API)
  "__isOverridable__": (module, name, arity) => {
    const moduleKey = module.value;
    const funKey = `${name.value}/${arity.value}`;

    if (!overridableRegistry.has(moduleKey)) {
      return false;
    }

    const moduleFuns = overridableRegistry.get(moduleKey);
    return moduleFuns.has(funKey);
  },
};

export default Erlang_Elixir_Overridable;

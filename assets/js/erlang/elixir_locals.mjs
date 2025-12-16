"use strict";

import Erlang_Maps from "./maps.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Locals = {
  // Start yank/2
  "yank/2": (locals, key) => {
    if (!Type.isMap(locals)) {
      Interpreter.raiseBadMapError(locals);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (!(encodedKey in locals.data)) {
      return Type.atom("error");
    }

    const value = locals.data[encodedKey][1];
    const newLocals = Erlang_Maps["remove/2"](key, locals);

    return Type.tuple([value, newLocals]);
  },
  // End yank/2
  // Deps: [:maps.remove/2]
};

export default Erlang_Elixir_Locals;

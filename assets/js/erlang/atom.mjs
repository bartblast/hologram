"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Atom = {
  // Start to_string/1
  "to_string/1": (atom) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Convert atom to string (binary)
    const str = atom.value;
    const encoder = new TextEncoder();
    const bytes = encoder.encode(str);
    return Type.bitstring(bytes, 0);
  },
  // End to_string/1
  // Deps: []

  // Start to_charlist/1
  "to_charlist/1": (atom) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Convert atom to character list
    const str = atom.value;
    const chars = [...str].map((char) => Type.integer(char.charCodeAt(0)));
    return Type.list(chars);
  },
  // End to_charlist/1
  // Deps: []
};

export default Erlang_Atom;

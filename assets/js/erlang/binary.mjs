"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Binary = {
  // Start first/1
  "first/1": (subject) => {
    if (!Type.isBinary(subject) && Type.isBitstring(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    }

    if (!Type.isBinary(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);

    if (Bitstring.isEmpty(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    }

    return Type.integer(subject.bytes[0]);
  },
  // End first/1
  // Deps: []
};

export default Erlang_Binary;

"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Binary = {
  // Start at/2
  "at/2": function (subject, pos) {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":binary.at/2", arguments),
      );
    }

    if (!Type.isInteger(pos) || pos.value < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":binary.at/2", arguments),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);

    if (pos.value >= subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    return Type.integer(subject.bytes[pos.value]);
  },
  // End at/2
  // Deps: []
};

export default Erlang_Binary;

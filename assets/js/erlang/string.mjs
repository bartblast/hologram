"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_String = {
  // Start join/2
  // Note: In Erlang, string() refers to charlists (lists of character codes)
  "join/2": function (stringList, separator) {
    if (!Type.isList(stringList)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.join/2", arguments),
      );
    }

    // Handle empty list case - Erlang's string:join/2 requires non-empty list
    if (stringList.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":string.join/2", arguments),
      );
    }

    // Join the strings (charlists) with separator
    const result = [];
    for (let i = 0; i < stringList.data.length; i++) {
      if (i > 0) {
        result.push(...separator.data);
      }
      result.push(...stringList.data[i].data);
    }

    return Type.list(result);
  },
  // End join/2
  // Deps: []
};

export default Erlang_String;

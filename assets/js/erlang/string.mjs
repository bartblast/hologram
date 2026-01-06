"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Helper: Check if a term is a charlist (list of integers)
function isCharlist(term) {
  if (!Type.isProperList(term)) {
    return false;
  }
  return term.data.every((element) => Type.isInteger(element));
}

const Erlang_String = {
  // Start join/2
  // -spec join(StringList, Separator) -> String
  //        when StringList :: [string()], Separator :: string(), String :: string().
  "join/2": function (stringList, separator) {
    const errorMsg = Interpreter.buildFunctionClauseErrorMsg(
      ":string.join/2",
      arguments,
    );

    // Validate stringList is a list (pattern matching)
    if (!Type.isList(stringList)) {
      Interpreter.raiseFunctionClauseError(errorMsg);
    }

    // Validate stringList is a proper list (per spec, prevent crashes)
    if (!Type.isProperList(stringList)) {
      Interpreter.raiseFunctionClauseError(errorMsg);
    }

    // Validate separator is a charlist (per spec, prevent crashes)
    if (!isCharlist(separator)) {
      Interpreter.raiseFunctionClauseError(errorMsg);
    }

    // Handle empty list case - return empty list
    if (stringList.data.length === 0) {
      return Type.list([]);
    }

    // Validate all elements in stringList are charlists (per spec, prevent crashes)
    for (const element of stringList.data) {
      if (!isCharlist(element)) {
        Interpreter.raiseFunctionClauseError(errorMsg);
      }
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

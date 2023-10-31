"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Lists = {
  // start flatten/1
  "flatten/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :lists.flatten/1",
      );
    }

    const data = list.data.reduce((acc, elem) => {
      if (Type.isList(elem)) {
        elem = Erlang_Lists["flatten/1"](elem);
        return acc.concat(elem.data);
      } else {
        return acc.concat(elem);
      }
    }, []);

    return Type.list(data);
  },
  // end flatten/1
  // deps: []

  // start reverse/1
  "reverse/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :lists.reverse/1",
      );
    }

    return Type.list(list.data.toReversed());
  },
  // end reverse/1
  // deps: []
};

export default Erlang_Lists;

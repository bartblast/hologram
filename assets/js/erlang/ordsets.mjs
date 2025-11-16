"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Ordsets = {
  // Start is_element/2
  "is_element/2": (element, ordset) => {
    if (!Type.isList(ordset)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Ordsets are ordered sets represented as sorted lists
    // Use binary search for efficiency
    const data = ordset.data;
    let left = 0;
    let right = data.length - 1;

    while (left <= right) {
      const mid = Math.floor((left + right) / 2);
      const comparison = Interpreter.compareTerms(element, data[mid]);

      if (comparison === 0) {
        return Type.boolean(true);
      } else if (comparison < 0) {
        right = mid - 1;
      } else {
        left = mid + 1;
      }
    }

    return Type.boolean(false);
  },
  // End is_element/2
  // Deps: []
};

export default Erlang_Ordsets;

"use strict";

import Interpreter from "../interpreter.mjs";
import Utils from "../utils.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_String = {
  // Start titlecase/1
  "titlecase/1": (subject) => {
    if (Type.isBitstring(subject)) {
      const clone = subject.text.slice(0);

      let firstchar = clone.charAt(0).toUpperCase();
      const remainder = clone.slice(1);

      if (firstchar === "SS") {
        firstchar = "Ss";
      }

      return Type.bitstring(firstchar + remainder);
    }

    if (Type.isList(subject)) {
      if (subject.data.length === 0) {
        return Type.list([]);
      }

      let clone = Utils.shallowCloneArray(subject.data);

      const first = clone[0];

      const firstChar = String.fromCodePoint(Number(first.value))
        .toUpperCase()
        .codePointAt(0);

      clone[0] = Type.integer(firstChar);

      return Type.list(clone);
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [subject]),
    );
  },
  // End titlecase/1
  // Deps: []
};

export default Erlang_String;

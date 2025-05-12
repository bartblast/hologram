"use strict";

import Bitstring2 from "../bitstring2.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Aliases = {
  // Start concat/1
  "concat/1": function (segments) {
    if (!Type.isList(segments)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":elixir_aliases.do_concat/2", [
          arguments[0],
          Type.bitstring2("Elixir"),
        ]),
      );
    }

    const normalizedSegments = segments.data.reduce((acc, segment, index) => {
      if (!Type.isAtom(segment) && !Type.isBinary2(segment)) {
        if (acc.length === 0 || !Interpreter.isEqual(acc[0], "Elixir")) {
          acc.unshift("Elixir");
        }

        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(
            ":elixir_aliases.do_concat/2",
            [
              Type.list(segments.data.slice(index)),
              Type.bitstring2(acc.join(".")),
            ],
          ),
        );
      }

      if (Type.isNil(segment)) {
        return acc;
      }

      let str = Type.isAtom(segment)
        ? segment.value
        : Bitstring2.toText(segment);

      if (str.startsWith("Elixir.")) {
        str = str.substring(7);
      } else if (str.startsWith(".")) {
        str = str.substring(1);
      }

      acc.push(str);

      return acc;
    }, []);

    if (normalizedSegments[0] !== "Elixir") {
      normalizedSegments.unshift("Elixir");
    }

    return Type.atom(normalizedSegments.join("."));
  },
  // End concat/1
  // Deps: []
};

export default Erlang_Elixir_Aliases;

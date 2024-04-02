"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Elixir_Aliases = {
  // start concat/1
  "concat/1": (segments) => {
    if (!Type.isList(segments)) {
      Interpreter.raiseFunctionClauseError(
        "no function clause matching in :elixir_aliases.do_concat/2",
      );
    }

    const normalizedSegments = segments.data.reduce((acc, segment) => {
      if (!Type.isAtom(segment) && !Type.isBinary(segment)) {
        Interpreter.raiseFunctionClauseError(
          "no function clause matching in :elixir_aliases.do_concat/2",
        );
      }

      if (Type.isNil(segment)) {
        return acc;
      }

      let str = Type.isAtom(segment)
        ? segment.value
        : Bitstring.toText(segment);

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
  // end concat/1
  // Deps: []
};

export default Erlang_Elixir_Aliases;

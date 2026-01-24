"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Erlang from "./erlang.mjs";

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
          Type.bitstring("Elixir"),
        ]),
      );
    }

    const normalizedSegments = segments.data.reduce((acc, segment, index) => {
      if (!Type.isAtom(segment) && !Type.isBinary(segment)) {
        if (acc.length === 0 || acc[0] !== "Elixir") {
          acc.unshift("Elixir");
        }

        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(
            ":elixir_aliases.do_concat/2",
            [
              Type.list(segments.data.slice(index)),
              Type.bitstring(acc.join(".")),
            ],
          ),
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
  // End concat/1
  // Deps: []
  // Note: due to dependency on :erlang.binary_to_existing_atom/1 the behaviour of the client version is inconsistent
  // with the server version.
  // The client version works exactly the same as concat/1.
  // Start safe_concat/1
  "safe_concat/1": function (segments) {
    const concat_atom = Erlang_Elixir_Aliases["concat/1"](segments);
    const concat_result = Erlang["atom_to_binary/1"](concat_atom);
    const result = Erlang["binary_to_existing_atom/1"](concat_result);

    return result;
  },
  // End safe_concat/1
  // Deps: [:elixir_aliases.concat/1, :erlang.binary_to_existing_atom/1]
};

export default Erlang_Elixir_Aliases;

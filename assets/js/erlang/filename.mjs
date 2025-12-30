"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Erlang from "./erlang.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Filename = {
  // Start basename/1
  "basename/1": (filename) => {
    let filepathText;
    let returnAsCodepoints = false;

    if (Type.isBinary(filename)) {
      Bitstring.maybeSetTextFromBytes(filename);
      filepathText = filename.text;
    } else if (Type.isList(filename)) {
      if (filename.data.length === 0) {
        return Type.list([]);
      }

      const binary = Erlang["iolist_to_binary/1"](filename);
      Bitstring.maybeSetTextFromBytes(binary);
      filepathText = binary.text;
      returnAsCodepoints = true;
    } else if (Type.isAtom(filename)) {
      filepathText = filename.value;
      returnAsCodepoints = true;
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
          filename,
          Type.list([]),
        ]),
      );
    }

    const parts = filepathText.split("/").filter((part) => part !== "");
    const basenameText = parts.length > 0 ? parts.at(-1) : "";
    const basenameBitstring = Type.bitstring(basenameText);

    return returnAsCodepoints
      ? Bitstring.toCodepoints(basenameBitstring)
      : basenameBitstring;
  },
  // End basename/1
  // Deps: [:erlang.iolist_to_binary/1]
};

export default Erlang_Filename;

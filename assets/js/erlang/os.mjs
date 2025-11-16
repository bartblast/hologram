"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Os = {
  // Start find_executable/1
  "find_executable/1": (name) => {
    // Convert name to string
    let nameStr;
    if (Type.isBinary(name)) {
      Bitstring.maybeSetBytesFromText(name);
      nameStr = new TextDecoder("utf-8").decode(name.bytes);
    } else if (Type.isList(name)) {
      const chars = name.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError("argument error");
        }
        return String.fromCharCode(Number(elem.value));
      });
      nameStr = chars.join("");
    } else if (Type.isAtom(name)) {
      nameStr = name.value;
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary, list, or atom"),
      );
    }

    // In a browser/JavaScript environment, we can't actually search the filesystem
    // for executables like we would in a real OS. This is a simplified implementation
    // that returns false (executable not found) since we're running in a browser context.
    //
    // In a real Erlang system, this would search PATH for the executable.
    // For Hologram's client-side runtime, executables don't apply.

    return Type.boolean(false);
  },
  // End find_executable/1
  // Deps: []
};

export default Erlang_Os;

"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

function toString(input) {
  if (Type.isBinary(input)) {
    Bitstring.maybeSetBytesFromText(input);
    return new TextDecoder("utf-8").decode(input.bytes);
  } else if (Type.isList(input)) {
    const chars = input.data.map((elem) => {
      if (!Type.isInteger(elem)) {
        return String(elem);
      }
      return String.fromCharCode(Number(elem.value));
    });
    return chars.join("");
  } else {
    return Interpreter.inspect(input);
  }
}

const Erlang_Logger = {
  // Start error/2
  "error/2": (message, metadata) => {
    // In the browser, log to console.error
    const msg = toString(message);

    if (Type.isMap(metadata) || Type.isList(metadata)) {
      console.error("[Logger] " + msg, metadata);
    } else {
      console.error("[Logger] " + msg);
    }

    return Type.atom("ok");
  },
  // End error/2
  // Deps: []
};

export default Erlang_Logger;

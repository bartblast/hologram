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
        throw new Error("not a valid string");
      }
      return String.fromCharCode(Number(elem.value));
    });
    return chars.join("");
  } else {
    throw new Error("not a valid string");
  }
}

function toBinary(str) {
  const bytes = new TextEncoder().encode(str);
  return Type.bitstring(bytes, 0);
}

const Erlang_Filelib = {
  // Start safe_relative_path/2
  "safe_relative_path/2": (filename, cwd) => {
    try {
      const path = toString(filename);
      const cwdPath = toString(cwd);

      // Normalize paths by removing . and .. segments
      const normalize = (p) => {
        const parts = p.split("/").filter((part) => part !== "" && part !== ".");
        const result = [];

        for (const part of parts) {
          if (part === "..") {
            if (result.length > 0 && result[result.length - 1] !== "..") {
              result.pop();
            } else {
              // Going above root
              return null;
            }
          } else {
            result.push(part);
          }
        }

        return result.join("/");
      };

      // Check if path is absolute
      if (path.startsWith("/")) {
        return Type.atom("unsafe");
      }

      // Normalize the path
      const normalized = normalize(path);

      if (normalized === null) {
        // Path tries to go above root
        return Type.atom("unsafe");
      }

      // Path is safe and relative
      return Type.tuple([Type.atom("ok"), toBinary(normalized)]);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End safe_relative_path/2
  // Deps: []
};

export default Erlang_Filelib;

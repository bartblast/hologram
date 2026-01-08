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

  // Start flatten/1
  "flatten/1": (filename) => {
    // Binary input returns binary unchanged
    if (Type.isBinary(filename)) {
      return filename;
    }

    // Everything else is delegated to _do_flatten/2
    return Erlang_Filename["_do_flatten/2"](filename, Type.list([]));
  },
  // End flatten/1
  // Deps: [:filename._do_flatten/2]

  // Start _do_flatten/2
  "_do_flatten/2": (filename, tail) => {
    // Handle list - recursively flatten each element
    if (Type.isList(filename)) {
      const flattenElement = (acc, elem) => {
        if (Type.isList(elem)) {
          return Erlang_Filename["_do_flatten/2"](elem, acc);
        }

        if (Type.isAtom(elem)) {
          const atomAsCharlist = Erlang["atom_to_list/1"](elem);
          const combined = [...atomAsCharlist.data, ...acc.data];
          return Type.list(combined);
        }

        const combined = [elem, ...acc.data];
        return Type.list(combined);
      };

      return filename.data.reduceRight(flattenElement, tail);
    }

    // Handle atom - convert to charlist and concatenate with tail
    if (Type.isAtom(filename)) {
      const atomAsCharlist = Erlang["atom_to_list/1"](filename);
      const combined = [...atomAsCharlist.data, ...tail.data];
      return Type.list(combined);
    }

    // Handle binary - add to front of tail
    if (Type.isBinary(filename)) {
      const combined = [filename, ...tail.data];
      return Type.list(combined);
    }

    // Invalid input - doesn't match any valid clause
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
        filename,
        tail,
      ]),
    );
  },
  // End _do_flatten/2
  // Deps: [:erlang.atom_to_list/1]
};

export default Erlang_Filename;

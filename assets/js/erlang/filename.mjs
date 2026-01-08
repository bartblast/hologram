"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Erlang from "./erlang.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Filename = {
  // Start _do_flatten/2
  "_do_flatten/2": (filename, tail) => {
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

    if (Type.isAtom(filename)) {
      const atomAsCharlist = Erlang["atom_to_list/1"](filename);
      const combined = [...atomAsCharlist.data, ...tail.data];
      return Type.list(combined);
    }

    if (Type.isBinary(filename)) {
      const combined = [filename, ...tail.data];
      return Type.list(combined);
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
        filename,
        tail,
      ]),
    );
  },
  // End _do_flatten/2
  // Deps: [:erlang.atom_to_list/1]

  // Start basename/1
  "basename/1": (filename) => {
    const DIR_SEPARATOR_BYTE = 47;

    // flatten/1 handles argument type checking and raises
    // FunctionClauseError if needed.
    const flattened = Erlang_Filename["flatten/1"](filename);

    // TODO: Once implemented, replace extractBasenameBytes with :binary.split/3
    // on <<"/">> with [global] option, filter out <<>>, and use :lists.last/1
    // (again once implemented) to get the last component.

    const extractBasenameBytes = (bytes) => {
      const lastNonSeparatorIndex = [...bytes]
        .reverse()
        .findIndex((byte) => byte !== DIR_SEPARATOR_BYTE);

      if (lastNonSeparatorIndex === -1) {
        return null;
      }

      const end = bytes.length - lastNonSeparatorIndex;
      const bytesUpToEnd = bytes.slice(0, end);

      const lastSeparatorIndex = [...bytesUpToEnd]
        .reverse()
        .findIndex((byte) => byte === DIR_SEPARATOR_BYTE);

      const start =
        lastSeparatorIndex === -1
          ? 0
          : bytesUpToEnd.length - lastSeparatorIndex;

      return bytes.slice(start, end);
    };

    const handleBinaryFilename = (flattened) => {
      if (Bitstring.isEmpty(flattened)) {
        return Type.bitstring("");
      }

      Bitstring.maybeSetBytesFromText(flattened);

      const bytes = flattened.bytes;

      const component = extractBasenameBytes(bytes);

      if (component === null) {
        return Type.bitstring("");
      }

      const basenameBinary = Bitstring.fromBytes(component);

      Bitstring.maybeSetTextFromBytes(basenameBinary);

      return Type.bitstring(basenameBinary.text);
    };

    const handleListFilename = (flattened) => {
      const binary = Erlang["iolist_to_binary/1"](flattened);
      Bitstring.maybeSetBytesFromText(binary);

      const bytes = binary.bytes;

      const component = extractBasenameBytes(bytes);

      if (component === null) {
        return Type.list([]);
      }

      const basenameBinary = Bitstring.fromBytes(component);

      return Bitstring.toCodepoints(basenameBinary);
    };

    const result = Type.isBinary(flattened)
      ? handleBinaryFilename(flattened)
      : handleListFilename(flattened);

    return result;
  },
  // End basename/1
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1]

  // Start flatten/1
  "flatten/1": (filename) => {
    if (Type.isBinary(filename)) {
      return filename;
    }

    return Erlang_Filename["_do_flatten/2"](filename, Type.list());
  },
  // End flatten/1
  // Deps: [:filename._do_flatten/2]
};

export default Erlang_Filename;

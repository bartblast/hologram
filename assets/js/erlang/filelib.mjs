"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Filename from "./filename.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Filelib = {
  // Start safe_relative_path/2
  "safe_relative_path/2": (filename, cwd) => {
    // Validate filename type (must be binary, charlist, or atom - filename_all())
    const isFilenameInvalid =
      !Type.isBinary(filename) &&
      !Type.isList(filename) &&
      !Type.isAtom(filename);

    // Validate cwd type (must be binary, charlist, or atom - filename_all())
    const isCwdInvalid =
      !Type.isBinary(cwd) && !Type.isList(cwd) && !Type.isAtom(cwd);

    if (isFilenameInvalid || isCwdInvalid) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("safe_relative_path/2", [
          filename,
          cwd,
        ]),
      );
    }

    // Note: In OTP, cwd is used to build absolute paths for each segment in order
    // to call :file.read_link/1 and detect symlinks that would escape the relative
    // root (see srp_segment/4 in filelib.erl). This is not applicable in a browser
    // environment, so only pure path sanitization (removing ".", resolving "..",
    // rejecting absolute paths) is performed here.

    const DIR_SEPARATOR_BYTE = 47;
    const isBinaryInput = Type.isBinary(filename);

    // Helpers

    const buildBinaryResult = (bytes) => {
      const resultBinary = Bitstring.fromBytes(bytes);
      Bitstring.maybeSetTextFromBytes(resultBinary);
      if (resultBinary.text === false) return resultBinary;
      return Type.bitstring(resultBinary.text);
    };

    const buildCharlistResult = (bytes) => {
      const chars = bytes.map((byte) => {
        if (Type.isInteger(byte)) return byte;
        return Type.integer(byte);
      });
      return Type.list(chars);
    };

    const extendArray = (arr, elem) => {
      if (Type.isList(elem)) return [...arr, ...elem.data];

      if (!Type.isBinary(elem)) return arr;

      Bitstring.maybeSetBytesFromText(elem);

      if (!elem.bytes) return arr;

      return [...arr, ...elem.bytes];
    };

    const isAbsolutePath = (part) => partToString(part) === "/";

    const isCurrentDir = (part) => partToString(part) === ".";

    const isParentDir = (part) => partToString(part) === "..";

    const toNumber = (elem) => {
      if (typeof elem === "bigint") return Number(elem);
      if (elem.value !== undefined) return Number(elem.value);
      return Number(elem);
    };

    const partToString = (part) => {
      if (Type.isList(part)) {
        try {
          const codes = part.data.map((elem) => {
            if (!Type.isInteger(elem)) return null;
            return toNumber(elem);
          });

          if (codes.some((code) => code === null)) return null;
          return String.fromCharCode(...codes);
        } catch {
          return null;
        }
      }

      if (!Type.isBinary(part)) return null;

      if (part.text === false) return null;

      return part.text;
    };

    // Main Logic

    // Split the path into components
    const pathParts = Erlang_Filename["split/1"](filename);
    if (!Type.isList(pathParts)) return Type.atom("unsafe");

    // Process path components to build sanitized path
    const sanitizedParts = pathParts.data.reduce(
      (result, part) => {
        if (result.isUnsafe) return result;

        // Absolute paths are unsafe
        if (result.parts.length === 0 && isAbsolutePath(part)) {
          return {...result, isUnsafe: true};
        }

        // Skip current directory markers
        if (isCurrentDir(part)) return result;

        // Parent directory marker
        if (isParentDir(part)) {
          const canGoUp = result.parts.length > 0;
          return canGoUp
            ? {...result, parts: result.parts.slice(0, -1)}
            : {...result, isUnsafe: true};
        }

        // Regular path component
        return {
          ...result,
          parts: [...result.parts, part],
        };
      },
      {parts: [], isUnsafe: false},
    );

    if (sanitizedParts.isUnsafe) return Type.atom("unsafe");

    if (sanitizedParts.parts.length === 0) return Type.list([]);

    // Rejoin path components with separator
    const joinedBytes = sanitizedParts.parts.reduce((bytes, part, index) => {
      const withPart = extendArray(bytes, part);
      const isLastPart = index === sanitizedParts.parts.length - 1;
      return isLastPart ? withPart : [...withPart, DIR_SEPARATOR_BYTE];
    }, []);

    // Build result based on input type
    return isBinaryInput
      ? buildBinaryResult(joinedBytes)
      : buildCharlistResult(joinedBytes);
  },
  // End safe_relative_path/2
  // Deps: [:filename.split/1]
};

export default Erlang_Filelib;

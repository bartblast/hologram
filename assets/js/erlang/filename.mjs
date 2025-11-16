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

const Erlang_Filename = {
  // Start basename/1
  "basename/1": (filename) => {
    try {
      const path = toString(filename);

      // Remove trailing slashes
      const trimmed = path.replace(/\/+$/, "");

      // Get last component
      const lastSlash = trimmed.lastIndexOf("/");
      const basename = lastSlash === -1 ? trimmed : trimmed.substring(lastSlash + 1);

      return toBinary(basename);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End basename/1
  // Deps: []

  // Start basename/2
  "basename/2": (filename, ext) => {
    try {
      const path = toString(filename);
      const extension = toString(ext);

      // Remove trailing slashes
      const trimmed = path.replace(/\/+$/, "");

      // Get last component
      const lastSlash = trimmed.lastIndexOf("/");
      let basename = lastSlash === -1 ? trimmed : trimmed.substring(lastSlash + 1);

      // Remove extension if it matches
      if (basename.endsWith(extension)) {
        basename = basename.substring(0, basename.length - extension.length);
      }

      return toBinary(basename);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End basename/2
  // Deps: []

  // Start dirname/1
  "dirname/1": (filename) => {
    try {
      const path = toString(filename);

      // Remove trailing slashes
      const trimmed = path.replace(/\/+$/, "");

      // Special cases
      if (trimmed === "" || trimmed === "/") {
        return toBinary("/");
      }

      // Get directory part
      const lastSlash = trimmed.lastIndexOf("/");

      if (lastSlash === -1) {
        return toBinary(".");
      } else if (lastSlash === 0) {
        return toBinary("/");
      } else {
        return toBinary(trimmed.substring(0, lastSlash));
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End dirname/1
  // Deps: []

  // Start extension/1
  "extension/1": (filename) => {
    try {
      const path = toString(filename);

      // Get basename
      const lastSlash = path.lastIndexOf("/");
      const basename = lastSlash === -1 ? path : path.substring(lastSlash + 1);

      // Find last dot
      const lastDot = basename.lastIndexOf(".");

      // Extension must not be at the beginning and must exist
      if (lastDot > 0) {
        return toBinary(basename.substring(lastDot));
      } else {
        return toBinary("");
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End extension/1
  // Deps: []

  // Start join/1
  "join/1": (components) => {
    if (!Type.isList(components)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    try {
      const parts = components.data.map((c) => toString(c));

      // Join with / and normalize
      let joined = parts.join("/");

      // Remove duplicate slashes
      joined = joined.replace(/\/+/g, "/");

      // Remove trailing slash unless it's root
      if (joined.length > 1 && joined.endsWith("/")) {
        joined = joined.substring(0, joined.length - 1);
      }

      return toBinary(joined);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End join/1
  // Deps: []

  // Start join/2
  "join/2": (name1, name2) => {
    try {
      const part1 = toString(name1);
      const part2 = toString(name2);

      // Handle absolute path in second component
      if (part2.startsWith("/")) {
        return toBinary(part2);
      }

      // Handle empty parts
      if (part1 === "") {
        return toBinary(part2);
      }
      if (part2 === "") {
        return toBinary(part1);
      }

      // Join with /
      let joined = part1.endsWith("/") ? part1 + part2 : part1 + "/" + part2;

      // Normalize double slashes
      joined = joined.replace(/\/+/g, "/");

      return toBinary(joined);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End join/2
  // Deps: []

  // Start rootname/1
  "rootname/1": (filename) => {
    try {
      const path = toString(filename);

      // Get basename
      const lastSlash = path.lastIndexOf("/");
      const dirPart = lastSlash === -1 ? "" : path.substring(0, lastSlash + 1);
      const basename = lastSlash === -1 ? path : path.substring(lastSlash + 1);

      // Find last dot in basename
      const lastDot = basename.lastIndexOf(".");

      // Extension must not be at the beginning
      if (lastDot > 0) {
        return toBinary(dirPart + basename.substring(0, lastDot));
      } else {
        return toBinary(path);
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End rootname/1
  // Deps: []

  // Start rootname/2
  "rootname/2": (filename, ext) => {
    try {
      const path = toString(filename);
      const extension = toString(ext);

      // Remove extension if it matches at the end
      if (path.endsWith(extension)) {
        return toBinary(path.substring(0, path.length - extension.length));
      } else {
        return toBinary(path);
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End rootname/2
  // Deps: []
};

export default Erlang_Filename;

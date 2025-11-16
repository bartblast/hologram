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
        return elem;
      }
      return String.fromCharCode(Number(elem.value));
    });
    return chars.join("");
  } else {
    return input;
  }
}

const Erlang_Io_Lib = {
  // Start format/2
  "format/2": (format, args) => {
    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    try {
      let formatStr = toString(format);
      const argValues = args.data;
      let argIndex = 0;

      // Simple format string parser
      // Supports: ~p (inspect), ~s (string), ~w (write), ~B (integer), ~.2f (float)
      const result = formatStr.replace(/~([0-9.]*)([pswBfn])/g, (match, modifier, type) => {
        if (argIndex >= argValues.length) {
          return match;
        }

        const arg = argValues[argIndex++];

        switch (type) {
          case 'p': // Pretty print
          case 'w': // Write
            return Interpreter.inspect(arg);

          case 's': // String
            return toString(arg);

          case 'B': // Integer
            if (Type.isInteger(arg)) {
              return arg.value.toString();
            }
            return Interpreter.inspect(arg);

          case 'f': // Float
            if (Type.isNumber(arg)) {
              const num = Number(arg.value);
              if (modifier) {
                const decimals = parseInt(modifier.replace('.', ''));
                return num.toFixed(decimals);
              }
              return num.toString();
            }
            return Interpreter.inspect(arg);

          case 'n': // Newline
            argIndex--; // Don't consume argument
            return '\n';

          default:
            return match;
        }
      });

      // Convert result string to character list
      const chars = [...result].map((char) => Type.integer(char.charCodeAt(0)));
      return Type.list(chars);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End format/2
  // Deps: []
};

export default Erlang_Io_Lib;

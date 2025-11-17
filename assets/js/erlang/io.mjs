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
    return Interpreter.inspect(input);
  }
}

const Erlang_Io = {
  // Start format/1
  "format/1": (format) => {
    // Delegate to format/2 with empty list
    return Erlang_Io["format/2"](format, Type.list([]));
  },
  // End format/1
  // Deps: [:io.format/2]

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
      // Supports: ~p (inspect), ~s (string), ~w (write), ~B (integer), ~.2f (float), ~n (newline)
      const result = formatStr.replace(/~([0-9.]*)([pswBfn])/g, (match, modifier, type) => {
        if (type === 'n') {
          // Newline doesn't consume an argument
          return '\n';
        }

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

          default:
            return match;
        }
      });

      // In browser context, output to console
      console.log(result);

      return Type.atom("ok");
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End format/2
  // Deps: []

  // Start nl/0
  "nl/0": () => {
    // Print a newline to console
    console.log("");
    return Type.atom("ok");
  },
  // End nl/0
  // Deps: []

  // Start put_chars/1
  "put_chars/1": (charData) => {
    try {
      const str = toString(charData);
      // In browser context, output to console without newline
      // Note: console.log always adds a newline, but this is close enough
      console.log(str);
      return Type.atom("ok");
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End put_chars/1
  // Deps: []

  // Start put_chars/2
  "put_chars/2": (device, charData) => {
    // Ignore device in browser context, just print to console
    try {
      const str = toString(charData);
      console.log(str);
      return Type.atom("ok");
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End put_chars/2
  // Deps: []
};

export default Erlang_Io;

"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Kernel = {
  "inspect/1": (term) => {
    return Elixir_Kernel["inspect/2"](term, Type.list([]));
  },

  // TODO: finish (e.g. implement text detection in binaries and other types such as pid, etc.)
  "inspect/2": (term, opts) => {
    let output;

    switch (term.type) {
      // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
      case "atom":
        if (Type.isBoolean(term) || Type.isNil(term)) {
          output = term.value;
        } else {
          output = ":" + term.value;
        }
        break;

      // case "float":
      //   if (Number.isInteger(term.value)) {
      //     output = term.value.toString() + ".0";
      //   } else {
      //     output = term.value.toString();
      //   }

      // case "integer":
      //   output = term.value.toString();

      // case "list":
      //   if (term.isProper) {
      //     output = (
      //       "[" +
      //       term.data
      //         .map((item) => Elixir_Kernel["inspect/1"](item, opts))
      //         .join(", ") +
      //       "]"
      //     );
      //   } else {
      //     output = (
      //       "[" +
      //       term.data
      //         .slice(0, -1)
      //         .map((item) => Elixir_Kernel["inspect/1"](item, opts))
      //         .join(", ") +
      //       " | " +
      //       Elixir_Kernel["inspect/1"](term.data.slice(-1)[0]) +
      //       "]"
      //     );
      //   }

      // case "string":
      //   return '"' + term.value.toString() + '"';

      // case "tuple":
      //   return (
      //     "{" +
      //     term.data.map((item) => Elixir_Kernel["inspect/1"](item)).join(", ") +
      //     "}"
      //   );

      // TODO: remove when all types are supported
      default:
        output = Interpreter.serialize(term);
    }

    return Type.bitstring(output);
  },
};

export default Elixir_Kernel;

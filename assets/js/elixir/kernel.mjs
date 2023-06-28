/*
This is only implemented to make testing easier, it is not included in the project build.
Project builds link Elixir_Kernel dynamically from automatically transpiled code.
*/

"use strict";

import Hologram from "../hologram.mjs";

const Type = Hologram.Type;

const Elixir_Kernel = {
  inspect: (term) => {
    switch (term.type) {
      // TODO: handle correctly atoms which need to be double quoted, e.g. :"1"
      case "atom":
        if (Type.isBoolean(term) || Type.isNil(term)) {
          return term.value;
        }
        return ":" + term.value;

      // TODO: case "bitstring"

      case "float":
        if (Number.isInteger(term.value)) {
          return term.value.toString() + ".0";
        } else {
          return term.value.toString();
        }

      case "integer":
        return term.value.toString();

      case "list":
        return (
          "[" +
          term.data.map((item) => Elixir_Kernel.inspect(item)).join(", ") +
          "]"
        );

      case "string":
        return '"' + term.value.toString() + '"';

      case "tuple":
        return (
          "{" +
          term.data.map((item) => Elixir_Kernel.inspect(item)).join(", ") +
          "}"
        );

      default:
        return Hologram.serialize(term);
    }
  },
};

export default Elixir_Kernel;

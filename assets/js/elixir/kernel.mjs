"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Kernel = {
  // Deps: [Kernel.inspect/2]
  "inspect/1": (term) => {
    return Elixir_Kernel["inspect/2"](term, Type.keywordList());
  },

  "inspect/2": (term, opts) => {
    return Type.bitstring(Interpreter.inspect(term, opts));
  },
};

export default Elixir_Kernel;

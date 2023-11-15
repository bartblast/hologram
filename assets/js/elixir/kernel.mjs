"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Kernel = {
  "inspect/1": (term) => {
    return Elixir_Kernel["inspect/2"](term, Type.list([]));
  },

  // TODO: support opts param
  "inspect/2": (term, _opts) => {
    return Type.bitstring(Interpreter.inspect(term, {}));
  },
};

export default Elixir_Kernel;

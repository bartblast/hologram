"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Kernel = {
  "inspect/1": (term) => {
    return Elixir_Kernel["inspect/2"](term, Type.list([]));
  },

  // TODO: support opts param
  "inspect/2": (term, _opts) => {
    const text = Bitstring.toText(Interpreter.inspect(term, {}));
    return Type.bitstring(text);
  },
};

export default Elixir_Kernel;
